const std = @import("std");
const posix = std.posix;
const c = std.c;

pub const WatchEventKind = enum { modified, created, deleted };
pub const WatchEvent = struct {
    path: []const u8,
    kind: WatchEventKind,
};

/// Per-directory state: open fd + current file snapshot (name -> mtime)
const DirState = struct {
    path: []const u8,
    files: std.StringHashMap(i128), // filename -> mtime ns

    fn deinit(self: *DirState, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        var it = self.files.keyIterator();
        while (it.next()) |k| allocator.free(k.*);
        self.files.deinit();
    }
};

pub const Watcher = struct {
    kq: posix.fd_t,
    dir_states: std.AutoHashMap(posix.fd_t, *DirState),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Watcher {
        return .{
            .kq = try posix.kqueue(),
            .dir_states = std.AutoHashMap(posix.fd_t, *DirState).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Watcher) void {
        var it = self.dir_states.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit(self.allocator);
            self.allocator.destroy(entry.value_ptr.*);
            posix.close(entry.key_ptr.*);
        }
        self.dir_states.deinit();
        posix.close(self.kq);
    }

    pub fn watchDir(self: *Watcher, path: []const u8) !void {
        try self.watchDirRecursive(path);
    }

    fn watchDirRecursive(self: *Watcher, path: []const u8) !void {
        const dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return;
        const fd = dir.fd;
        // Don't close dir here — we keep fd open for kqueue

        const kev = posix.Kevent{
            .ident = @intCast(fd),
            .filter = c.EVFILT.VNODE,
            .flags = c.EV.ADD | c.EV.CLEAR | c.EV.ENABLE,
            .fflags = c.NOTE.WRITE | c.NOTE.DELETE | c.NOTE.RENAME,
            .data = 0,
            .udata = 0,
        };
        _ = posix.kevent(self.kq, &.{kev}, &.{}, null) catch {
            posix.close(fd);
            return;
        };

        const state = try self.allocator.create(DirState);
        state.* = .{
            .path = try self.allocator.dupe(u8, path),
            .files = std.StringHashMap(i128).init(self.allocator),
        };
        try buildSnapshot(self.allocator, path, &state.files);
        try self.dir_states.put(fd, state);

        // Recurse into subdirectories
        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind != .directory) continue;
            const sub = try std.fs.path.join(self.allocator, &.{ path, entry.name });
            defer self.allocator.free(sub);
            try self.watchDirRecursive(sub);
        }
    }

    pub fn poll(self: *Watcher, out: *std.ArrayList(WatchEvent), timeout_ms: i32) !usize {
        var events: [32]posix.Kevent = undefined;

        var ts_storage: posix.timespec = undefined;
        const ts_ptr: ?*const posix.timespec = if (timeout_ms >= 0) blk: {
            ts_storage = .{
                .sec = @intCast(@divFloor(timeout_ms, 1000)),
                .nsec = @intCast(@mod(timeout_ms, 1000) * std.time.ns_per_ms),
            };
            break :blk &ts_storage;
        } else null;

        const n = posix.kevent(self.kq, &.{}, &events, ts_ptr) catch return 0;
        const before = out.items.len;

        for (events[0..n]) |ev| {
            const fd: posix.fd_t = @intCast(ev.ident);
            const state_ptr = self.dir_states.getPtr(fd) orelse continue;
            const state = state_ptr.*;

            // Build new snapshot and diff against old
            var new_files = std.StringHashMap(i128).init(self.allocator);
            buildSnapshot(self.allocator, state.path, &new_files) catch {
                new_files.deinit();
                continue;
            };

            // Emit created / modified
            var nit = new_files.iterator();
            while (nit.next()) |entry| {
                if (state.files.get(entry.key_ptr.*)) |old_mtime| {
                    if (old_mtime != entry.value_ptr.*) {
                        const p = try std.fs.path.join(self.allocator, &.{ state.path, entry.key_ptr.* });
                        try out.append(self.allocator, .{ .path = p, .kind = .modified });
                    }
                } else {
                    const p = try std.fs.path.join(self.allocator, &.{ state.path, entry.key_ptr.* });
                    try out.append(self.allocator, .{ .path = p, .kind = .created });
                }
            }

            // Emit deleted
            var oit = state.files.iterator();
            while (oit.next()) |entry| {
                if (!new_files.contains(entry.key_ptr.*)) {
                    const p = try std.fs.path.join(self.allocator, &.{ state.path, entry.key_ptr.* });
                    try out.append(self.allocator, .{ .path = p, .kind = .deleted });
                }
            }

            // Swap snapshot
            var kit = state.files.keyIterator();
            while (kit.next()) |k| self.allocator.free(k.*);
            state.files.deinit();
            state.files = new_files;
        }

        return out.items.len - before;
    }
};

fn buildSnapshot(allocator: std.mem.Allocator, path: []const u8, files: *std.StringHashMap(i128)) !void {
    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return;
    defer dir.close();
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;
        const stat = dir.statFile(entry.name) catch continue;
        const key = try allocator.dupe(u8, entry.name);
        try files.put(key, stat.mtime);
    }
}
