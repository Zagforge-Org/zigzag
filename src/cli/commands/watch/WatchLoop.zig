const std = @import("std");
const State = @import("State.zig");
const reporter = @import("reporter.zig");
const Config = @import("../config/Config.zig");
const Pool = @import("../../../workers/Pool.zig");
const Cache = @import("../../../cache/Cache.zig");
const watcher_mod = @import("../../../platform/watcher.zig");
const Watcher = watcher_mod.Watcher;
const WatchEvent = watcher_mod.WatchEvent;
const report = @import("../report.zig");
const Server = @import("Server.zig");
const log = @import("../../../logger/Logger.zig");

const Self = @This();

allocator: std.mem.Allocator,
io: std.Io,
cfg: *Config,
cache: ?*Cache,
pool: *Pool,
states: []*State,
sse_server: ?*Server,
base_out_dir: []const u8,
watcher: *Watcher,
events: std.ArrayList(WatchEvent) = .empty,

// Per-state dirty flags so only changed paths get reports rebuilt.
dirty_states: []bool,

// File paths changed in the current debounce window.
changed_paths: std.ArrayList([]const u8) = .empty,
any_dirty: bool = false,
any_overflow: bool = false,

// Group rapid-fire events into a single update to preserve CPU.
const debounce_ms: i32 = 50;

pub fn init(
    allocator: std.mem.Allocator,
    io: std.Io,
    cfg: *Config,
    cache: ?*Cache,
    pool: *Pool,
    states: []*State,
    sse_server: ?*Server,
    base_out_dir: []const u8,
    watcher: *Watcher,
) !Self {
    const dirty_states = try allocator.alloc(bool, states.len);
    @memset(dirty_states, false);
    return .{
        .io = io,
        .cfg = cfg,
        .cache = cache,
        .pool = pool,
        .states = states,
        .sse_server = sse_server,
        .base_out_dir = base_out_dir,
        .allocator = allocator,
        .watcher = watcher,
        .dirty_states = dirty_states,
    };
}

pub fn run(self: *Self) void {
    while (true) {
        self.events.clearRetainingCapacity();

        const timeout: i32 = if (self.any_dirty) debounce_ms else -1;
        const n = self.watcher.poll(&self.events, timeout) catch |err| {
            log.err(self.io, "Watcher poll error: {s}", .{@errorName(err)});
            continue;
        };

        if (self.watcher.overflow) self.handleOverflow();

        if (n > 0) {
            for (self.events.items) |event| {
                defer self.allocator.free(event.path);
                self.handleEvent(event);
            }
        } else if (self.any_dirty) {
            // Rebuild reports for the paths that changed.
            self.flush();
        }
    }
}

// Handle inotify queue overflow by marking all states dirty and let the debounce
// flush rebuild reports from current in memory state.
pub fn handleOverflow(self: *Self) void {
    self.watcher.overflow = false;
    self.any_overflow = true;
    @memset(self.dirty_states, true);
    self.any_dirty = true;
}

/// Route a single filesystem event to the first state whose root contains it.
pub fn handleEvent(self: *Self, event: WatchEvent) void {
    if (isIgnoredEventPath(event.path, self.base_out_dir)) return;

    for (self.states, 0..) |state, i| {
        if (!std.mem.startsWith(u8, event.path, state.root_path)) continue;

        switch (event.kind) {
            .created, .modified => self.applyUpsert(state, event.path),
            .deleted => self.applyDelete(state, event.path),
        }
        self.dirty_states[i] = true;
        self.any_dirty = true;
        return;
    }
}

/// Re-process a created/modified file and push its delta to connected clients.
fn applyUpsert(self: *Self, state: *State, path: []const u8) void {
    state.updateFile(path, self.cache, self.pool) catch |err| {
        log.err(self.io, "Failed to process {s}: {s}", .{ path, @errorName(err) });
    };
    // Track the changed path for selective sidecar writes on debounce.
    const path_copy = self.allocator.dupe(u8, path) catch null;
    if (path_copy) |p| self.changed_paths.append(self.allocator, p) catch self.allocator.free(p);
    // Broadcast a small KB-sized delta immediately.
    self.broadcastUpsert(state, path);
}

fn broadcastUpsert(self: *Self, state: *State, path: []const u8) void {
    const srv = self.sse_server orelse return;
    state.entries_mutex.lockUncancelable(self.io);
    const entry_opt = state.file_entries.get(path);
    state.entries_mutex.unlock(self.io);
    const entry = entry_opt orelse return;
    const delta = report.buildFileDeltaPayload(self.allocator, &entry) catch return;
    defer self.allocator.free(delta);
    srv.broadcast(delta);
}

/// Drop a deleted file from memory and notify connected clients.
fn applyDelete(self: *Self, state: *State, path: []const u8) void {
    state.removeFile(path);
    const srv = self.sse_server orelse return;
    const delta = report.buildFileDeletePayload(self.allocator, path) catch return;
    defer self.allocator.free(delta);
    srv.broadcast(delta);
}

/// Write reports only for paths that actually changed during the debounce window.
pub fn flush(self: *Self) void {
    const any_state_dirty = std.mem.indexOfScalar(bool, self.dirty_states, true) != null;

    // On overflow, changed_paths is incomplete.
    const paths_for_write: []const []const u8 = if (self.any_overflow) &.{} else self.changed_paths.items;

    // Write combined report FIRST so it is on disk before the SSE "report" event
    // fires and causes connected browsers to reload combined.html.
    // Only write and signal the combined dashboard in multi-path mode; single-path
    // watch uses SSE deltas and the per-state report event instead.
    // `writeCombinedReport` handles the `broadcastCombined` SSE push internally.
    if (any_state_dirty and self.states.len > 1) {
        reporter.writeCombinedReport(self.io, self.states, self.cfg, self.sse_server, paths_for_write, self.allocator);
    }
    for (self.states, 0..) |state, i| {
        if (!self.dirty_states[i]) continue;
        reporter.writeAllReports(self.io, state, self.cfg, self.sse_server, paths_for_write, self.allocator);
        self.dirty_states[i] = false;
    }
    self.any_dirty = false;
    self.any_overflow = false;
    self.clearChangedPaths();
}

pub fn deinit(self: *Self) void {
    self.events.deinit(self.allocator);
    self.clearChangedPaths();
    self.changed_paths.deinit(self.allocator);
    self.allocator.free(self.dirty_states);
}

fn clearChangedPaths(self: *Self) void {
    for (self.changed_paths.items) |p| self.allocator.free(p);
    self.changed_paths.clearRetainingCapacity();
}

/// Filesystem events under the cache or report-output directories are self-inflicted
/// and must never trigger a rebuild.
pub fn isIgnoredEventPath(path: []const u8, base_out_dir: []const u8) bool {
    return std.mem.indexOf(u8, path, ".cache") != null or
        std.mem.indexOf(u8, path, ".zig-cache") != null or
        std.mem.indexOf(u8, path, base_out_dir) != null;
}
