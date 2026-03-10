const std = @import("std");
const windows = std.os.windows;
const watch_api = @import("../../platform/windows/watch.zig");

pub const WatchEventKind = enum { modified, created, deleted };
pub const WatchEvent = struct {
    path: []const u8,
    kind: WatchEventKind,
};

const DEFAULT_SKIP_DIRS = @import("./skip_dirs.zig").DEFAULT_SKIP_DIRS;

/// Thread-safe event queue shared between background watch threads and poll().
/// Heap-allocated and ref-counted so both the Watcher and each watchThread can
/// hold a reference; the queue is only freed when the last holder releases it.
const SharedQueue = struct {
    mutex: std.Thread.Mutex = .{},
    events: std.ArrayList(WatchEvent) = .empty,
    allocator: std.mem.Allocator,
    ref: std.atomic.Value(u32),

    fn create(allocator: std.mem.Allocator) !*SharedQueue {
        const q = try allocator.create(SharedQueue);
        q.* = .{ .allocator = allocator, .ref = std.atomic.Value(u32).init(1) };
        return q;
    }

    fn retain(self: *SharedQueue) void {
        _ = self.ref.fetchAdd(1, .monotonic);
    }

    fn release(self: *SharedQueue) void {
        if (self.ref.fetchSub(1, .acq_rel) == 1) {
            for (self.events.items) |ev| self.allocator.free(ev.path);
            self.events.deinit(self.allocator);
            self.allocator.destroy(self);
        }
    }

    fn push(self: *SharedQueue, ev: WatchEvent) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.events.append(self.allocator, ev) catch {};
    }

    fn drain(self: *SharedQueue, out: *std.ArrayList(WatchEvent)) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try out.appendSlice(self.allocator, self.events.items);
        self.events.clearRetainingCapacity();
    }
};

/// Context passed to each background watch thread.
/// Watcher owns the ctx; the thread borrows it. Watcher calls thread.join()
/// before freeing ctx, so no ref-counting is needed here.
const WatchCtx = struct {
    path: []const u8,
    queue: *SharedQueue,
    allocator: std.mem.Allocator,
    stop: std.atomic.Value(bool),
    /// Directory handle stored as usize; 0 = not yet opened or already closed.
    /// Allows deinit() to close it from outside, unblocking ReadDirectoryChangesW.
    dir_handle: std.atomic.Value(usize),
    thread: std.Thread,
};

fn watchThread(ctx: *WatchCtx) void {
    // Convert path to null-terminated UTF-16
    var path_w_buf: [std.fs.max_path_bytes]u16 = undefined;
    const path_w_len = std.unicode.utf8ToUtf16Le(&path_w_buf, ctx.path) catch return;
    path_w_buf[path_w_len] = 0;

    const dir_handle = watch_api.CreateFileW(
        @ptrCast(&path_w_buf),
        watch_api.FILE_LIST_DIRECTORY,
        windows.FILE_SHARE_READ | windows.FILE_SHARE_WRITE | windows.FILE_SHARE_DELETE,
        null,
        windows.OPEN_EXISTING,
        watch_api.FILE_FLAG_BACKUP_SEMANTICS,
        null,
    );
    if (dir_handle == windows.INVALID_HANDLE_VALUE) return;

    // If stop was already signalled before we opened the handle, close and exit.
    if (ctx.stop.load(.acquire)) {
        _ = windows.CloseHandle(dir_handle);
        return;
    }

    // Publish handle so deinit() can close it to interrupt a blocked ReadDirectoryChangesW.
    ctx.dir_handle.store(@intFromPtr(dir_handle), .release);

    var buf: [65536]u8 align(4) = undefined;

    while (!ctx.stop.load(.acquire)) {
        var bytes_returned: u32 = 0;
        const ok = watch_api.ReadDirectoryChangesW(
            dir_handle,
            &buf,
            buf.len,
            windows.TRUE,
            watch_api.FILE_NOTIFY_CHANGE_LAST_WRITE |
                watch_api.FILE_NOTIFY_CHANGE_FILE_NAME |
                watch_api.FILE_NOTIFY_CHANGE_DIR_NAME,
            &bytes_returned,
            null,
            null,
        );
        if (ok == windows.FALSE or bytes_returned == 0) continue;

        var offset: usize = 0;
        while (offset + @sizeOf(watch_api.FileNotifyInformation) <= bytes_returned) {
            const info: *align(1) const watch_api.FileNotifyInformation = @ptrCast(&buf[offset]);

            const name_offset = offset + @sizeOf(watch_api.FileNotifyInformation);
            const name_u16: []const u16 = @as(
                [*]const u16,
                @ptrCast(@alignCast(&buf[name_offset])),
            )[0 .. info.FileNameLength / @sizeOf(u16)];

            var name_buf: [std.fs.max_path_bytes]u8 = undefined;
            const name_len = std.unicode.utf16LeToUtf8(&name_buf, name_u16) catch {
                if (info.NextEntryOffset == 0) break;
                offset += info.NextEntryOffset;
                continue;
            };
            const name_utf8 = name_buf[0..name_len];

            if (std.fs.path.join(ctx.allocator, &.{ ctx.path, name_utf8 })) |full_path| {
                const kind: WatchEventKind = switch (info.Action) {
                    watch_api.FILE_ACTION_ADDED,
                    watch_api.FILE_ACTION_RENAMED_NEW_NAME,
                    => .created,
                    watch_api.FILE_ACTION_REMOVED,
                    watch_api.FILE_ACTION_RENAMED_OLD_NAME,
                    => .deleted,
                    else => .modified,
                };
                ctx.queue.push(.{ .path = full_path, .kind = kind });
            } else |_| {}

            if (info.NextEntryOffset == 0) break;
            offset += info.NextEntryOffset;
        }
    }

    // Close the handle ourselves only if deinit() hasn't already done so.
    const h = ctx.dir_handle.swap(0, .acq_rel);
    if (h != 0) _ = windows.CloseHandle(@ptrFromInt(h));
}

pub const Watcher = struct {
    queue: *SharedQueue,
    ctxs: std.ArrayList(*WatchCtx) = .empty,
    allocator: std.mem.Allocator,
    /// Set when events may have been lost; always false on Windows (API parity with linux.zig).
    overflow: bool = false,
    /// Directory names to filter out of poll() results (basename component match).
    skip_dirs: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) !Watcher {
        var skip_dirs: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (skip_dirs.items) |d| allocator.free(d);
            skip_dirs.deinit(allocator);
        }
        for (DEFAULT_SKIP_DIRS) |dir| {
            try skip_dirs.append(allocator, try allocator.dupe(u8, dir));
        }
        return .{
            .queue = try SharedQueue.create(allocator),
            .allocator = allocator,
            .skip_dirs = skip_dirs,
        };
    }

    pub fn deinit(self: *Watcher) void {
        for (self.ctxs.items) |ctx| {
            // Signal the thread to stop.
            ctx.stop.store(true, .release);
            // Close the directory handle to unblock a pending ReadDirectoryChangesW.
            const h = ctx.dir_handle.swap(0, .acq_rel);
            if (h != 0) _ = windows.CloseHandle(@ptrFromInt(h));
            // Wait for the thread to fully exit before freeing shared resources.
            ctx.thread.join();
            ctx.queue.release();
            self.allocator.free(ctx.path);
            self.allocator.destroy(ctx);
        }
        self.ctxs.deinit(self.allocator);
        self.queue.release();
        for (self.skip_dirs.items) |d| self.allocator.free(d);
        self.skip_dirs.deinit(self.allocator);
    }

    /// Register a directory name to skip when filtering poll() events.
    /// The basename is compared against path components relative to the watched root,
    /// so "zigzag-reports" filters events from that subdirectory at any depth without
    /// accidentally matching ancestor directories in the root path.
    /// Call before watchDir().
    pub fn addSkipDir(self: *Watcher, dir: []const u8) !void {
        const name = std.fs.path.basename(dir);
        if (name.len == 0) return;
        const copy = try self.allocator.dupe(u8, name);
        try self.skip_dirs.append(self.allocator, copy);
    }

    /// Returns true if any component of `path` RELATIVE to a registered watch root
    /// matches a skip directory name.  Checking only the relative portion means the
    /// root directory's own ancestor components (e.g. ".zig-cache" in a temp-dir path)
    /// are never matched, which mirrors the Linux/macOS behaviour where only
    /// subdirectories *inside* the watched tree are skipped.
    fn shouldSkipPath(self: *const Watcher, path: []const u8) bool {
        // Find which registered root this event belongs to and strip it,
        // so we only inspect components relative to the watched root.
        for (self.ctxs.items) |ctx| {
            if (!std.mem.startsWith(u8, path, ctx.path)) continue;
            var rel = path[ctx.path.len..];
            if (rel.len > 0 and rel[0] == std.fs.path.sep) rel = rel[1..];
            var it = std.mem.splitScalar(u8, rel, std.fs.path.sep);
            while (it.next()) |component| {
                if (component.len == 0) continue;
                for (self.skip_dirs.items) |skip| {
                    if (std.mem.eql(u8, component, skip)) return true;
                }
            }
            return false;
        }
        return false;
    }

    pub fn watchDir(self: *Watcher, path: []const u8) !void {
        const ctx = try self.allocator.create(WatchCtx);
        errdefer self.allocator.destroy(ctx);

        const path_copy = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(path_copy);

        self.queue.retain(); // ctx holds one queue ref; released in deinit() after join
        errdefer self.queue.release();

        ctx.* = .{
            .path = path_copy,
            .queue = self.queue,
            .allocator = self.allocator,
            .stop = std.atomic.Value(bool).init(false),
            .dir_handle = std.atomic.Value(usize).init(0),
            .thread = undefined,
        };

        ctx.thread = try std.Thread.spawn(.{}, watchThread, .{ctx});
        try self.ctxs.append(self.allocator, ctx);
    }

    pub fn poll(self: *Watcher, out: *std.ArrayList(WatchEvent), timeout_ms: i32) !usize {
        const before = out.items.len;
        try self.drainFiltered(out);
        if (out.items.len > before) return out.items.len - before;
        if (timeout_ms == 0) return 0;

        // Wait up to timeout_ms for events (or indefinitely if -1)
        const wait_ms: u64 = if (timeout_ms < 0) std.math.maxInt(u64) else @intCast(timeout_ms);
        const start = std.time.milliTimestamp();
        while (true) {
            std.Thread.sleep(5 * std.time.ns_per_ms);
            try self.drainFiltered(out);
            if (out.items.len > before) break;
            if (@as(u64, @intCast(std.time.milliTimestamp() - start)) >= wait_ms) break;
        }
        return out.items.len - before;
    }

    /// Drain the shared queue into `out`, discarding events whose paths contain a
    /// registered skip directory component.
    fn drainFiltered(self: *Watcher, out: *std.ArrayList(WatchEvent)) !void {
        var raw: std.ArrayList(WatchEvent) = .empty;
        defer raw.deinit(self.allocator);
        try self.queue.drain(&raw);
        for (raw.items) |ev| {
            if (self.shouldSkipPath(ev.path)) {
                self.allocator.free(ev.path);
            } else {
                try out.append(self.allocator, ev);
            }
        }
    }
};
