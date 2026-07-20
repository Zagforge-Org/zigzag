//! Filesystem watcher backed by kqueue, with an mtime fallback scan for
//! in-place file edits (macOS/BSD).

const std = @import("std");
const posix = std.posix;
const c = std.c;

const sys = @import("kqueue.zig");
const DEFAULT_SKIP_DIRS = @import("../../utils/utils.zig").DEFAULT_SKIP_DIRS;

pub const WatchEventKind = @import("../watch_event.zig").WatchEventKind;
pub const WatchEvent = @import("../watch_event.zig").WatchEvent;

const Self = @This();

/// How often the mtime fallback scan runs (in nanoseconds).
/// kqueue NOTE_WRITE on a directory fd does NOT fire when an existing file's
/// content is modified in-place; it only fires for create/delete/rename.
/// This periodic scan catches in-place modifications by comparing mtimes.
const MTIME_POLL_INTERVAL_NS: i128 = 2 * std.time.ns_per_s;

/// The sweep covers EVERY watched directory each cycle so an in-place edit is
/// detected within one interval. (A previous design rotated through directories
/// in batches of 256, which stretched worst-case detection to minutes on large
/// trees — e.g. ~105 s for the ~13k watched dirs of a Next.js checkout and
/// made the dashboard feel unresponsive to plain in-place saves.)
/// To keep the poll thread's duty cycle bounded on pathological trees, the
/// interval stretches adaptively to SWEEP_DUTY_FACTOR x the measured sweep
/// duration when a sweep is slow.
const SWEEP_DUTY_FACTOR: i128 = 5;

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

io: std.Io,
kq: posix.fd_t,
dir_states: std.AutoHashMap(posix.fd_t, *DirState),
/// Ordered list of directory fds for round-robin mtime scanning.
/// Mirrors the keys in dir_states but provides stable iteration order.
dir_fds: std.ArrayList(posix.fd_t),
/// Inode numbers of directories already registered, used to deduplicate when
/// multiple watchDir() paths resolve to the same physical directory (e.g. "apps"
/// and "./apps" when "." is also a watched path).
seen_inodes: std.AutoHashMap(u64, void),
allocator: std.mem.Allocator,
/// Set when events may have been lost; always false on macOS (API parity with linux).
overflow: bool = false,
/// Directory basenames to skip when recursively registering kqueue watches.
skip_dirs: std.ArrayList([]const u8),
/// Timestamp of last mtime fallback scan.
last_mtime_scan: i128 = 0,
/// Current scan interval; MTIME_POLL_INTERVAL_NS unless sweeps measure slow.
mtime_scan_interval: i128 = MTIME_POLL_INTERVAL_NS,

pub fn init(io: std.Io, allocator: std.mem.Allocator) !Self {
    var skip_dirs: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (skip_dirs.items) |d| allocator.free(d);
        skip_dirs.deinit(allocator);
    }
    for (DEFAULT_SKIP_DIRS) |dir| {
        try skip_dirs.append(allocator, try allocator.dupe(u8, dir));
    }
    return .{
        .io = io,
        .kq = try sys.kqueue(),
        .dir_states = std.AutoHashMap(posix.fd_t, *DirState).init(allocator),
        .dir_fds = std.ArrayList(posix.fd_t).empty,
        .seen_inodes = std.AutoHashMap(u64, void).init(allocator),
        .allocator = allocator,
        .skip_dirs = skip_dirs,
        .last_mtime_scan = std.Io.Timestamp.now(io, .real).nanoseconds,
    };
}

pub fn deinit(self: *Self) void {
    var it = self.dir_states.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.*.deinit(self.allocator);
        self.allocator.destroy(entry.value_ptr.*);
        sys.close(entry.key_ptr.*);
    }
    self.dir_states.deinit();
    self.dir_fds.deinit(self.allocator);
    self.seen_inodes.deinit();
    sys.close(self.kq);
    for (self.skip_dirs.items) |d| self.allocator.free(d);
    self.skip_dirs.deinit(self.allocator);
}

/// Register a directory name to skip when adding kqueue watches.
/// Only the basename is compared, so "zigzag-reports" skips any directory
/// with that name at any depth. Call before watchDir().
pub fn addSkipDir(self: *Self, dir: []const u8) !void {
    const name = std.fs.path.basename(dir);
    if (name.len == 0) return;
    const copy = try self.allocator.dupe(u8, name);
    try self.skip_dirs.append(self.allocator, copy);
}

fn shouldSkipPath(self: *const Self, path: []const u8) bool {
    const name = std.fs.path.basename(path);
    if (name.len == 0) return false;
    for (self.skip_dirs.items) |skip| {
        if (std.mem.eql(u8, name, skip)) return true;
    }
    return false;
}

pub fn watchDir(self: *Self, path: []const u8) !void {
    try self.watchDirRecursive(path);
}

fn watchDirRecursive(self: *Self, path: []const u8) !void {
    if (self.shouldSkipPath(path)) return;
    const dir = std.Io.Dir.cwd().openDir(self.io, path, .{ .iterate = true }) catch return;
    const fd = dir.handle;

    // Deduplicate by inode: "apps" and "./apps" are the same physical directory.
    // Without this, multiple watchDir() calls for overlapping paths (e.g. "apps" + ".")
    // create redundant kqueue watches producing duplicate events.
    const stat = sys.fstat(fd) catch {
        sys.close(fd);
        return;
    };
    if ((try self.seen_inodes.getOrPut(@intCast(stat.ino))).found_existing) {
        sys.close(fd);
        return;
    }

    // Don't close dir here as we keep fd open for kqueue

    const kev = posix.Kevent{
        .ident = @intCast(fd),
        .filter = c.EVFILT.VNODE,
        .flags = c.EV.ADD | c.EV.CLEAR | c.EV.ENABLE,
        .fflags = c.NOTE.WRITE | c.NOTE.DELETE | c.NOTE.RENAME,
        .data = 0,
        .udata = 0,
    };
    _ = sys.kevent(self.kq, &.{kev}, &.{}, null) catch {
        sys.close(fd);
        return;
    };

    const state = try self.allocator.create(DirState);
    state.* = .{
        .path = try self.allocator.dupe(u8, path),
        .files = std.StringHashMap(i128).init(self.allocator),
    };
    try buildSnapshot(self.io, self.allocator, path, &state.files);
    try self.dir_states.put(fd, state);
    try self.dir_fds.append(self.allocator, fd);

    // Recurse into subdirectories
    var it = dir.iterate();
    while (try it.next(self.io)) |entry| {
        if (entry.kind != .directory) continue;
        const sub = try std.fs.path.join(self.allocator, &.{ path, entry.name });
        defer self.allocator.free(sub);
        try self.watchDirRecursive(sub);
    }
}

pub fn poll(self: *Self, out: *std.ArrayList(WatchEvent), timeout_ms: i32) !usize {
    // Cap the timeout so the mtime fallback scan runs periodically.
    // kqueue NOTE_WRITE on a directory fd does not fire for in-place file
    // modifications; only for create/delete/rename, so we must poll mtimes
    // to catch edits.
    const max_poll_ms: i32 = @intCast(@divFloor(MTIME_POLL_INTERVAL_NS, std.time.ns_per_ms));
    const effective_timeout = if (timeout_ms < 0) max_poll_ms else @min(timeout_ms, max_poll_ms);

    var events: [32]posix.Kevent = undefined;

    var ts_storage: posix.timespec = undefined;
    const ts_ptr: ?*const posix.timespec = if (effective_timeout >= 0) blk: {
        ts_storage = .{
            .sec = @intCast(@divFloor(effective_timeout, 1000)),
            .nsec = @intCast(@mod(effective_timeout, 1000) * std.time.ns_per_ms),
        };
        break :blk &ts_storage;
    } else null;

    const n = sys.kevent(self.kq, &.{}, &events, ts_ptr) catch return 0;
    const before = out.items.len;

    // Process kqueue events (create/delete/rename)
    for (events[0..n]) |ev| {
        const fd: posix.fd_t = @intCast(ev.ident);
        const state_ptr = self.dir_states.getPtr(fd) orelse continue;
        const state = state_ptr.*;
        try self.diffAndEmit(state, out);
    }

    // Periodic mtime sweep to catch in-place file modifications. Covers every
    // watched directory so detection latency is bounded by one interval; the
    // interval stretches when a sweep measures slow (huge trees, cold caches).
    const now = std.Io.Timestamp.now(self.io, .real).nanoseconds;
    if (now - self.last_mtime_scan >= self.mtime_scan_interval) {
        for (self.dir_fds.items) |fd| {
            // Skip dirs already diffed via a kqueue event this poll.
            var already_diffed = false;
            for (events[0..n]) |ev| {
                if (@as(posix.fd_t, @intCast(ev.ident)) == fd) {
                    already_diffed = true;
                    break;
                }
            }
            if (already_diffed) continue;

            if (self.dir_states.getPtr(fd)) |state_ptr| {
                try self.diffAndEmit(state_ptr.*, out);
            }
        }

        // Measure from sweep end so slow sweeps never overlap, and keep the
        // poll thread's sweep duty cycle at or below 1/SWEEP_DUTY_FACTOR.
        const done = std.Io.Timestamp.now(self.io, .real).nanoseconds;
        self.last_mtime_scan = done;
        self.mtime_scan_interval = @max(MTIME_POLL_INTERVAL_NS, (done - now) * SWEEP_DUTY_FACTOR);
    }

    return out.items.len - before;
}

/// Build a new snapshot for a directory, diff against the old one,
/// emit events, and swap the snapshot.
fn diffAndEmit(self: *Self, state: *DirState, out: *std.ArrayList(WatchEvent)) !void {
    var new_files = std.StringHashMap(i128).init(self.allocator);
    buildSnapshot(self.io, self.allocator, state.path, &new_files) catch {
        new_files.deinit();
        return;
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

fn buildSnapshot(io: std.Io, allocator: std.mem.Allocator, path: []const u8, files: *std.StringHashMap(i128)) !void {
    var dir = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch return;
    defer dir.close(io);
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        const stat = dir.statFile(io, entry.name, .{}) catch continue;
        const key = try allocator.dupe(u8, entry.name);
        try files.put(key, stat.mtime.nanoseconds);
    }
}
