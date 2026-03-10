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
/// Watcher owns the ctx; the thread borrows it. Watcher signals stop_event and
/// joins the thread before freeing ctx, so no ref-counting is needed on WatchCtx.
const WatchCtx = struct {
    path: []const u8,
    queue: *SharedQueue,
    allocator: std.mem.Allocator,
    /// Manual-reset Windows event. Signaled by deinit() to wake the thread out of
    /// WaitForMultipleObjects so it can exit cleanly without closing the dir handle
    /// from outside (which is not safe with overlapped I/O).
    stop_event: windows.HANDLE,
    thread: std.Thread,
};

fn watchThread(ctx: *WatchCtx) void {
    // Convert path to null-terminated UTF-16
    var path_w_buf: [std.fs.max_path_bytes]u16 = undefined;
    const path_w_len = std.unicode.utf8ToUtf16Le(&path_w_buf, ctx.path) catch return;
    path_w_buf[path_w_len] = 0;

    // Must open with FILE_FLAG_OVERLAPPED for async ReadDirectoryChangesW.
    const dir_handle = watch_api.CreateFileW(
        @ptrCast(&path_w_buf),
        watch_api.FILE_LIST_DIRECTORY,
        windows.FILE_SHARE_READ | windows.FILE_SHARE_WRITE | windows.FILE_SHARE_DELETE,
        null,
        windows.OPEN_EXISTING,
        watch_api.FILE_FLAG_BACKUP_SEMANTICS | watch_api.FILE_FLAG_OVERLAPPED,
        null,
    );
    if (dir_handle == windows.INVALID_HANDLE_VALUE) return;
    defer _ = windows.CloseHandle(dir_handle);

    // Manual-reset event for overlapped I/O completion; starts unsignaled.
    const io_event = watch_api.CreateEventW(null, windows.TRUE, windows.FALSE, null) orelse return;
    defer _ = windows.CloseHandle(io_event);

    var overlapped: watch_api.OVERLAPPED = .{ .hEvent = io_event };
    var buf: [65536]u8 align(4) = undefined;

    // Wait on both the I/O completion event and the stop event.
    const handles = [2]windows.HANDLE{ io_event, ctx.stop_event };

    const NOTIFY_FILTER =
        watch_api.FILE_NOTIFY_CHANGE_LAST_WRITE |
        watch_api.FILE_NOTIFY_CHANGE_FILE_NAME |
        watch_api.FILE_NOTIFY_CHANGE_DIR_NAME;

    while (true) {
        // Reset the I/O event and re-arm overlapped before each call.
        _ = watch_api.ResetEvent(io_event);
        overlapped = .{ .hEvent = io_event };

        const queued = watch_api.ReadDirectoryChangesW(
            dir_handle,
            &buf,
            buf.len,
            windows.TRUE,
            NOTIFY_FILTER,
            null, // lpBytesReturned must be null for overlapped
            &overlapped,
            null,
        );

        // With FILE_FLAG_OVERLAPPED the call returns FALSE + ERROR_IO_PENDING
        // when submitted successfully.  Any other error is fatal.
        if (queued == windows.FALSE and watch_api.GetLastError() != watch_api.ERROR_IO_PENDING) break;

        const wait = watch_api.WaitForMultipleObjects(2, &handles, windows.FALSE, watch_api.INFINITE);

        if (wait == watch_api.WAIT_OBJECT_0) {
            // I/O completed — retrieve the byte count.
            var bytes_returned: u32 = 0;
            if (watch_api.GetOverlappedResult(dir_handle, &overlapped, &bytes_returned, windows.FALSE) == windows.FALSE) continue;
            if (bytes_returned == 0) continue;

            // Process FILE_NOTIFY_INFORMATION records.
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
        } else {
            // stop_event signaled (or WAIT_FAILED) — cancel pending I/O and exit.
            _ = watch_api.CancelIo(dir_handle);
            var bytes_dummy: u32 = 0;
            // Wait for cancellation to complete before closing handles in defer.
            _ = watch_api.GetOverlappedResult(dir_handle, &overlapped, &bytes_dummy, windows.TRUE);
            break;
        }
    }
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
            // Signal the stop event to wake the thread from WaitForMultipleObjects.
            _ = watch_api.SetEvent(ctx.stop_event);
            // Wait for the thread to fully exit before freeing shared resources.
            ctx.thread.join();
            _ = windows.CloseHandle(ctx.stop_event);
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

        // Manual-reset event, initially not signaled; closed by deinit() after join().
        const stop_event = watch_api.CreateEventW(null, windows.TRUE, windows.FALSE, null) orelse
            return error.OutOfResources;
        errdefer _ = windows.CloseHandle(stop_event);

        self.queue.retain(); // ctx holds one queue ref; released in deinit() after join
        errdefer self.queue.release();

        ctx.* = .{
            .path = path_copy,
            .queue = self.queue,
            .allocator = self.allocator,
            .stop_event = stop_event,
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
