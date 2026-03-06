const std = @import("std");
const linux = std.os.linux;
const posix = std.posix;

pub const WatchEventKind = enum { modified, created, deleted };
pub const WatchEvent = struct {
    path: []const u8,
    kind: WatchEventKind,
};

pub const Watcher = struct {
    ifd: posix.fd_t,
    wd_map: std.AutoHashMap(i32, []const u8),
    allocator: std.mem.Allocator,
    buf: [65536]u8 align(@alignOf(linux.inotify_event)),

    const WATCH_MASK: u32 = linux.IN.CLOSE_WRITE | linux.IN.CREATE | linux.IN.DELETE |
        linux.IN.MOVED_FROM | linux.IN.MOVED_TO | linux.IN.DELETE_SELF;

    pub fn init(allocator: std.mem.Allocator) !Watcher {
        const fd = try posix.inotify_init1(linux.IN.CLOEXEC);
        return .{
            .ifd = fd,
            .wd_map = std.AutoHashMap(i32, []const u8).init(allocator),
            .allocator = allocator,
            .buf = undefined,
        };
    }

    pub fn deinit(self: *Watcher) void {
        var it = self.wd_map.valueIterator();
        while (it.next()) |v| self.allocator.free(v.*);
        self.wd_map.deinit();
        posix.close(self.ifd);
    }

    pub fn watchDir(self: *Watcher, path: []const u8) !void {
        try self.addWatchRecursive(path);
    }

    fn addWatchRecursive(self: *Watcher, path: []const u8) !void {
        const path_z = try self.allocator.dupeZ(u8, path);
        defer self.allocator.free(path_z);

        const wd = posix.inotify_add_watch(self.ifd, path_z, WATCH_MASK) catch |err| switch (err) {
            error.FileNotFound, error.NotDir => return,
            else => return err,
        };

        const gop = try self.wd_map.getOrPut(wd);
        if (gop.found_existing) {
            self.allocator.free(gop.value_ptr.*);
        }
        gop.value_ptr.* = try self.allocator.dupe(u8, path);

        var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return;
        defer dir.close();
        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind != .directory) continue;
            const sub = try std.fs.path.join(self.allocator, &.{ path, entry.name });
            defer self.allocator.free(sub);
            try self.addWatchRecursive(sub);
        }
    }

    fn removeWatchByPath(self: *Watcher, dir_path: []const u8) void {
        var found_wd: ?i32 = null;
        var it = self.wd_map.iterator();
        while (it.next()) |entry| {
            if (std.mem.eql(u8, entry.value_ptr.*, dir_path)) {
                found_wd = entry.key_ptr.*;
                break;
            }
        }
        if (found_wd) |wd| {
            _ = linux.inotify_rm_watch(self.ifd, wd);
            if (self.wd_map.fetchRemove(wd)) |kv| {
                self.allocator.free(kv.value);
            }
        }
    }

    pub fn poll(self: *Watcher, out: *std.ArrayList(WatchEvent), timeout_ms: i32) !usize {
        var pfds = [1]posix.pollfd{.{
            .fd = self.ifd,
            .events = posix.POLL.IN,
            .revents = 0,
        }};

        const n_ready = posix.poll(&pfds, timeout_ms) catch return 0;
        if (n_ready == 0) return 0;

        const bytes_read = posix.read(self.ifd, &self.buf) catch return 0;
        const before = out.items.len;

        var offset: usize = 0;
        while (offset + @sizeOf(linux.inotify_event) <= bytes_read) {
            const ev: *const linux.inotify_event = @ptrCast(@alignCast(self.buf[offset..].ptr));
            const ev_size = @sizeOf(linux.inotify_event) + ev.len;
            if (offset + ev_size > bytes_read) break;

            defer offset += ev_size;

            // Queue overflow
            if (ev.mask & linux.IN.Q_OVERFLOW != 0) {
                std.log.warn("inotify event queue overflow - some events lost", .{});
                continue;
            }

            // Watch auto-removed (after IN_DELETE_SELF or explicit rm_watch)
            if (ev.mask & linux.IN.IGNORED != 0) {
                if (self.wd_map.fetchRemove(ev.wd)) |kv| self.allocator.free(kv.value);
                continue;
            }

            const dir_path = self.wd_map.get(ev.wd) orelse continue;
            const name_start = offset + @sizeOf(linux.inotify_event);

            // New subdirectory created - add watches recursively
            if (ev.mask & linux.IN.CREATE != 0 and ev.mask & linux.IN.ISDIR != 0) {
                if (ev.len > 0) {
                    const name = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(self.buf[name_start..].ptr)), 0);
                    if (std.fs.path.join(self.allocator, &.{ dir_path, name })) |sub| {
                        defer self.allocator.free(sub);
                        self.addWatchRecursive(sub) catch {};
                    } else |_| {}
                }
                continue;
            }

            // Subdirectory deleted/moved - remove its watch
            if ((ev.mask & linux.IN.DELETE != 0 or ev.mask & linux.IN.MOVED_FROM != 0) and ev.mask & linux.IN.ISDIR != 0) {
                if (ev.len > 0) {
                    const name = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(self.buf[name_start..].ptr)), 0);
                    if (std.fs.path.join(self.allocator, &.{ dir_path, name })) |sub| {
                        defer self.allocator.free(sub);
                        self.removeWatchByPath(sub);
                    } else |_| {}
                }
                continue;
            }

            // Skip directory self-events
            if (ev.mask & linux.IN.ISDIR != 0) continue;
            if (ev.len == 0) continue;

            const name = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(self.buf[name_start..].ptr)), 0);
            const full_path = try std.fs.path.join(self.allocator, &.{ dir_path, name });

            const kind: WatchEventKind = if (ev.mask & (linux.IN.DELETE | linux.IN.MOVED_FROM) != 0)
                .deleted
            else if (ev.mask & (linux.IN.CREATE | linux.IN.MOVED_TO) != 0)
                .created
            else
                .modified; // CLOSE_WRITE

            try out.append(self.allocator, .{ .path = full_path, .kind = kind });
        }

        return out.items.len - before;
    }
};
