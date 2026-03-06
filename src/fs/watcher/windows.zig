const std = @import("std");
const windows = std.os.windows;
const watch_api = @import("../../platform/windows/watch.zig");

pub const WatchEventKind = enum { modified, created, deleted };
pub const WatchEvent = struct {
    path: []const u8,
    kind: WatchEventKind,
};

/// Thread-safe event queue shared between background watch threads and poll()
const SharedQueue = struct {
    mutex: std.Thread.Mutex = .{},
    events: std.ArrayList(WatchEvent) = .empty,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) SharedQueue {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *SharedQueue) void {
        for (self.events.items) |ev| self.allocator.free(ev.path);
        self.events.deinit(self.allocator);
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
/// Ref-counted (init=2: one for watcher, one for thread) so deinit() can signal
/// stop and release its ref without freeing memory the thread is still using.
const WatchCtx = struct {
    path: []const u8,
    queue: *SharedQueue,
    allocator: std.mem.Allocator,
    stop: std.atomic.Value(bool),
    ref: std.atomic.Value(u32),

    fn release(self: *WatchCtx) void {
        if (self.ref.fetchSub(1, .acq_rel) == 1) {
            self.allocator.free(self.path);
            self.allocator.destroy(self);
        }
    }
};

fn watchThread(ctx: *WatchCtx) void {
    defer ctx.release();
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
    defer _ = windows.CloseHandle(dir_handle);

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
}

pub const Watcher = struct {
    queue: SharedQueue,
    ctxs: std.ArrayList(*WatchCtx) = .empty,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Watcher {
        return .{
            .queue = SharedQueue.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Watcher) void {
        for (self.ctxs.items) |ctx| {
            ctx.stop.store(true, .release);
            ctx.release(); // release watcher's ref; thread frees ctx when it exits
        }
        self.ctxs.deinit(self.allocator);
        self.queue.deinit();
    }

    pub fn watchDir(self: *Watcher, path: []const u8) !void {
        const ctx = try self.allocator.create(WatchCtx);
        ctx.* = .{
            .path = try self.allocator.dupe(u8, path),
            .queue = &self.queue,
            .allocator = self.allocator,
            .stop = std.atomic.Value(bool).init(false),
            .ref = std.atomic.Value(u32).init(2),
        };
        try self.ctxs.append(self.allocator, ctx);
        const t = try std.Thread.spawn(.{}, watchThread, .{ctx});
        t.detach();
    }

    pub fn poll(self: *Watcher, out: *std.ArrayList(WatchEvent), timeout_ms: i32) !usize {
        const before = out.items.len;
        try self.queue.drain(out);
        if (out.items.len > before) return out.items.len - before;
        if (timeout_ms == 0) return 0;

        // Wait up to timeout_ms for events (or indefinitely if -1)
        const wait_ms: u64 = if (timeout_ms < 0) std.math.maxInt(u64) else @intCast(timeout_ms);
        const start = std.time.milliTimestamp();
        while (true) {
            std.Thread.sleep(5 * std.time.ns_per_ms);
            try self.queue.drain(out);
            if (out.items.len > before) break;
            if (@as(u64, @intCast(std.time.milliTimestamp() - start)) >= wait_ms) break;
        }
        return out.items.len - before;
    }
};
