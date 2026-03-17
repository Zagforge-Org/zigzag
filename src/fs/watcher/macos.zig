const std = @import("std");
const posix = std.posix;
const c = std.c;

pub const WatchEventKind = enum { modified, created, deleted };
pub const WatchEvent = struct {
    path: []const u8,
    kind: WatchEventKind,
};

const DEFAULT_SKIP_DIRS = @import("../../utils/utils.zig").DEFAULT_SKIP_DIRS;

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
    /// Inode numbers of directories already registered, used to deduplicate when
    /// multiple watchDir() paths resolve to the same physical directory (e.g. "apps"
    /// and "./apps" when "." is also a watched path).
    seen_inodes: std.AutoHashMap(u64, void),
    allocator: std.mem.Allocator,
    /// Set when events may have been lost; always false on macOS (API parity with linux.zig).
    overflow: bool = false,
    /// Directory basenames to skip when recursively registering kqueue watches.
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
            .kq = try posix.kqueue(),
            .dir_states = std.AutoHashMap(posix.fd_t, *DirState).init(allocator),
            .seen_inodes = std.AutoHashMap(u64, void).init(allocator),
            .allocator = allocator,
            .skip_dirs = skip_dirs,
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
        self.seen_inodes.deinit();
        posix.close(self.kq);
        for (self.skip_dirs.items) |d| self.allocator.free(d);
        self.skip_dirs.deinit(self.allocator);
    }

    /// Register a directory name to skip when adding kqueue watches.
    /// Only the basename is compared, so "zigzag-reports" skips any directory
    /// with that name at any depth. Call before watchDir().
    pub fn addSkipDir(self: *Watcher, dir: []const u8) !void {
        const name = std.fs.path.basename(dir);
        if (name.len == 0) return;
        const copy = try self.allocator.dupe(u8, name);
        try self.skip_dirs.append(self.allocator, copy);
    }

    fn shouldSkipPath(self: *const Watcher, path: []const u8) bool {
        const name = std.fs.path.basename(path);
        if (name.len == 0) return false;
        for (self.skip_dirs.items) |skip| {
            if (std.mem.eql(u8, name, skip)) return true;
        }
        return false;
    }

    pub fn watchDir(self: *Watcher, path: []const u8) !void {
        try self.watchDirRecursive(path);
    }

    fn watchDirRecursive(self: *Watcher, path: []const u8) !void {
        if (self.shouldSkipPath(path)) return;
        const dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return;
        const fd = dir.fd;

        // Deduplicate by inode: "apps" and "./apps" are the same physical directory.
        // Without this, multiple watchDir() calls for overlapping paths (e.g. "apps" + ".")
        // create redundant kqueue watches producing duplicate events.
        const stat = posix.fstat(fd) catch {
            posix.close(fd);
            return;
        };
        if ((try self.seen_inodes.getOrPut(@intCast(stat.ino))).found_existing) {
            posix.close(fd);
            return;
        }

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
