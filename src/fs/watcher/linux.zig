const std = @import("std");
const linux = std.os.linux;
const posix = std.posix;

pub const WatchEventKind = enum { modified, created, deleted };
pub const WatchEvent = struct {
    path: []const u8,
    kind: WatchEventKind,
};

/// Directories skipped by the file walker (shouldIgnore in process.zig).
/// The watcher must skip the same dirs so their writes never enter the inotify queue.
/// Matching is substring-based (same as matchesPattern path-contains logic).
const DEFAULT_SKIP_DIRS = [_][]const u8{
    "node_modules",
    ".git",
    ".svn",
    ".hg",
    "__pycache__",
    ".pytest_cache",
    ".idea",
    ".vscode",
    ".DS_Store",
    ".cache",
    ".zig-cache",
};

pub const Watcher = struct {
    ifd: posix.fd_t,
    wd_map: std.AutoHashMap(i32, []const u8),
    allocator: std.mem.Allocator,
    buf: [65536]u8 align(@alignOf(linux.inotify_event)),
    /// Set when IN_Q_OVERFLOW is received; caller should mark states dirty and rebuild.
    overflow: bool = false,
    /// Directories to skip when registering inotify watches (substring match on full path).
    /// Prevents high-churn directories (node_modules, output dirs, caches) from flooding
    /// the inotify event queue and triggering spurious overflows.
    skip_dirs: std.ArrayList([]const u8),

    const WATCH_MASK: u32 = linux.IN.CLOSE_WRITE | linux.IN.CREATE | linux.IN.DELETE |
        linux.IN.MOVED_FROM | linux.IN.MOVED_TO | linux.IN.DELETE_SELF;

    pub fn init(allocator: std.mem.Allocator) !Watcher {
        const fd = try posix.inotify_init1(linux.IN.CLOEXEC);
        errdefer posix.close(fd);

        var skip_dirs: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (skip_dirs.items) |d| allocator.free(d);
            skip_dirs.deinit(allocator);
        }
        for (DEFAULT_SKIP_DIRS) |dir| {
            try skip_dirs.append(allocator, try allocator.dupe(u8, dir));
        }

        return .{
            .ifd = fd,
            .wd_map = std.AutoHashMap(i32, []const u8).init(allocator),
            .allocator = allocator,
            .buf = undefined,
            .skip_dirs = skip_dirs,
        };
    }

    pub fn deinit(self: *Watcher) void {
        var it = self.wd_map.valueIterator();
        while (it.next()) |v| self.allocator.free(v.*);
        self.wd_map.deinit();
        posix.close(self.ifd);
        for (self.skip_dirs.items) |d| self.allocator.free(d);
        self.skip_dirs.deinit(self.allocator);
    }

    /// Register a directory name to skip when adding inotify watches.
    /// Only the basename (last path component) is compared, so "zigzag-reports" skips
    /// any directory with that name at any depth without affecting unrelated paths.
    /// Call this before watchDir() for output directories, custom ignore paths, etc.
    pub fn addSkipDir(self: *Watcher, dir: []const u8) !void {
        const name = std.fs.path.basename(dir);
        if (name.len == 0) return;
        const copy = try self.allocator.dupe(u8, name);
        try self.skip_dirs.append(self.allocator, copy);
    }

    pub fn watchDir(self: *Watcher, path: []const u8) !void {
        try self.addWatchRecursive(path);
    }

    /// Returns true when the LAST component of path matches any registered skip name.
    /// Matching only on basename means we skip e.g. node_modules at any depth without
    /// accidentally skipping unrelated paths that happen to contain "node_modules" as
    /// a substring of a parent directory (e.g. /home/user/.zig-cache/tmp/TestRun).
    fn shouldSkipPath(self: *const Watcher, path: []const u8) bool {
        const name = std.fs.path.basename(path);
        if (name.len == 0) return false;
        for (self.skip_dirs.items) |skip| {
            if (std.mem.eql(u8, name, skip)) return true;
        }
        return false;
    }

    fn addWatchRecursive(self: *Watcher, path: []const u8) !void {
        if (self.shouldSkipPath(path)) return;

        const path_z = try self.allocator.dupeZ(u8, path);
        defer self.allocator.free(path_z);

        const wd = posix.inotify_add_watch(self.ifd, path_z, WATCH_MASK) catch |err| switch (err) {
            error.FileNotFound, error.NotDir => return,
            error.SystemResources => {
                std.log.warn("inotify watch limit reached; increase fs.inotify.max_user_watches (e.g. sudo sysctl fs.inotify.max_user_watches=524288)", .{});
                return;
            },
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

            // Queue overflow — mark flag so caller can rebuild reports from in-memory state.
            if (ev.mask & linux.IN.Q_OVERFLOW != 0) {
                std.log.warn("inotify event queue overflow - some events lost", .{});
                self.overflow = true;
                continue;
            }

            // Watch auto-removed (after IN_DELETE_SELF or explicit rm_watch)
            if (ev.mask & linux.IN.IGNORED != 0) {
                if (self.wd_map.fetchRemove(ev.wd)) |kv| self.allocator.free(kv.value);
                continue;
            }

            const dir_path = self.wd_map.get(ev.wd) orelse continue;
            const name_start = offset + @sizeOf(linux.inotify_event);

            // New subdirectory created - add watches recursively (skip_dirs apply here too)
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
