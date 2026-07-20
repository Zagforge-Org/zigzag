const std = @import("std");
const testing = std.testing;
const WatchLoop = @import("WatchLoop.zig");
const State = @import("State.zig");
const Config = @import("../config/Config.zig");
const Pool = @import("../../../workers/Pool.zig");
const watcher_mod = @import("../../../platform/watcher.zig");
const Watcher = watcher_mod.Watcher;
const JobEntry = @import("../../../jobs/entries.zig").JobEntry;
const BinaryEntry = @import("../../../jobs/entries.zig").BinaryEntry;

/// Build a bare State without touching the filesystem/thread pool.
fn testState(alloc: std.mem.Allocator, root_path: []const u8, md_path: []const u8) State {
    var state: State = undefined;
    state.io = testing.io;
    state.root_path = root_path;
    state.md_path = md_path;
    state.file_entries = std.StringHashMap(JobEntry).init(alloc);
    state.binary_entries = std.StringHashMap(BinaryEntry).init(alloc);
    state.entries_mutex = .init;
    state.allocator = alloc;
    state.file_ctx = .{ .io = testing.io, .ignore_list = .empty, .md = undefined, .md_mutex = undefined };
    state.llm_memo = .init(alloc);
    state.defer_frees = false;
    state.graveyard_files = .empty;
    state.graveyard_binaries = .empty;
    return state;
}

fn deinitTestState(state: *State, alloc: std.mem.Allocator) void {
    state.llm_memo.deinit();
    state.graveyard_files.deinit(alloc);
    state.graveyard_binaries.deinit(alloc);
    state.file_entries.deinit();
    state.binary_entries.deinit();
    state.file_ctx.ignore_list.deinit(alloc);
}

/// Insert a source entry, duplicating every owned slice so State.removeFile can
/// free them cleanly under the testing allocator.
fn putSourceEntry(state: *State, alloc: std.mem.Allocator, path: []const u8) !void {
    const key = try alloc.dupe(u8, path);
    try state.file_entries.put(key, .{
        .path = key,
        .content = try alloc.dupe(u8, "pub fn f() void {}\n"),
        .size = 19,
        .mtime = 0,
        .extension = try alloc.dupe(u8, ".zig"),
        .line_count = 1,
    });
}

test "init clears every per-state dirty flag and starts with empty buffers" {
    const alloc = testing.allocator;
    var s = testState(alloc, "src", "report.md");
    defer deinitTestState(&s, alloc);
    var states = [_]*State{&s};

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    var pool: Pool = .{};
    var watcher: Watcher = undefined;

    var loop = try WatchLoop.init(alloc, testing.io, &cfg, null, &pool, states[0..], null, "zigzag-reports", &watcher);
    defer loop.deinit();

    try testing.expectEqual(@as(usize, 1), loop.dirty_states.len);
    try testing.expect(!loop.dirty_states[0]);
    try testing.expect(!loop.any_dirty);
    try testing.expect(!loop.any_overflow);
    try testing.expectEqual(@as(usize, 0), loop.changed_paths.items.len);
    try testing.expectEqual(@as(usize, 0), loop.events.items.len);
}

test "init sizes the dirty-flag array to the state count" {
    const alloc = testing.allocator;
    var s0 = testState(alloc, "src", "a.md");
    defer deinitTestState(&s0, alloc);
    var s1 = testState(alloc, "lib", "b.md");
    defer deinitTestState(&s1, alloc);
    var states = [_]*State{ &s0, &s1 };

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    var pool: Pool = .{};
    var watcher: Watcher = undefined;

    var loop = try WatchLoop.init(alloc, testing.io, &cfg, null, &pool, states[0..], null, "zigzag-reports", &watcher);
    defer loop.deinit();

    try testing.expectEqual(@as(usize, 2), loop.dirty_states.len);
}

test "handleOverflow marks all states dirty and clears the watcher flag" {
    const alloc = testing.allocator;
    var s0 = testState(alloc, "src", "a.md");
    defer deinitTestState(&s0, alloc);
    var s1 = testState(alloc, "lib", "b.md");
    defer deinitTestState(&s1, alloc);
    var states = [_]*State{ &s0, &s1 };

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    var pool: Pool = .{};
    var watcher = try Watcher.init(testing.io, alloc);
    defer watcher.deinit();
    watcher.overflow = true;

    var loop = try WatchLoop.init(alloc, testing.io, &cfg, null, &pool, states[0..], null, "zigzag-reports", &watcher);
    defer loop.deinit();

    loop.handleOverflow();

    try testing.expect(!watcher.overflow);
    try testing.expect(loop.any_overflow);
    try testing.expect(loop.any_dirty);
    for (loop.dirty_states) |d| try testing.expect(d);
}

test "handleEvent ignores self-inflicted events under the output dir" {
    const alloc = testing.allocator;
    var s = testState(alloc, "src", "report.md");
    defer deinitTestState(&s, alloc);
    var states = [_]*State{&s};

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    var pool: Pool = .{};
    var watcher: Watcher = undefined;

    var loop = try WatchLoop.init(alloc, testing.io, &cfg, null, &pool, states[0..], null, "zigzag-reports", &watcher);
    defer loop.deinit();

    // Path is under the report output dir must be skipped before any state match.
    loop.handleEvent(.{ .path = "src/zigzag-reports/report-content.json", .kind = .modified });

    try testing.expect(!loop.dirty_states[0]);
    try testing.expect(!loop.any_dirty);
}

test "handleEvent skips paths outside every watched root" {
    const alloc = testing.allocator;
    var s = testState(alloc, "src", "report.md");
    defer deinitTestState(&s, alloc);
    var states = [_]*State{&s};

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    var pool: Pool = .{};
    var watcher: Watcher = undefined;

    var loop = try WatchLoop.init(alloc, testing.io, &cfg, null, &pool, states[0..], null, "zigzag-reports", &watcher);
    defer loop.deinit();

    // No state root matches "docs/…", so the event is dropped without dispatch
    // (in particular, applyUpsert which needs the pool is never reached).
    loop.handleEvent(.{ .path = "docs/guide.md", .kind = .modified });

    try testing.expect(!loop.dirty_states[0]);
    try testing.expect(!loop.any_dirty);
}

test "handleEvent delete removes the entry and marks its state dirty" {
    const alloc = testing.allocator;
    var s = testState(alloc, "src", "report.md");
    defer deinitTestState(&s, alloc);
    try putSourceEntry(&s, alloc, "src/gone.zig");
    var states = [_]*State{&s};

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    var pool: Pool = .{};
    var watcher: Watcher = undefined;

    var loop = try WatchLoop.init(alloc, testing.io, &cfg, null, &pool, states[0..], null, "zigzag-reports", &watcher);
    defer loop.deinit();

    loop.handleEvent(.{ .path = "src/gone.zig", .kind = .deleted });

    try testing.expectEqual(@as(usize, 0), s.file_entries.count());
    try testing.expect(loop.dirty_states[0]);
    try testing.expect(loop.any_dirty);
}

test "handleEvent routes an event to the first matching root only" {
    const alloc = testing.allocator;
    var s0 = testState(alloc, "src", "a.md");
    defer deinitTestState(&s0, alloc);
    var s1 = testState(alloc, "lib", "b.md");
    defer deinitTestState(&s1, alloc);
    var states = [_]*State{ &s0, &s1 };

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    var pool: Pool = .{};
    var watcher: Watcher = undefined;

    var loop = try WatchLoop.init(alloc, testing.io, &cfg, null, &pool, states[0..], null, "zigzag-reports", &watcher);
    defer loop.deinit();

    // "lib/…" belongs to the second state; the first must stay clean.
    loop.handleEvent(.{ .path = "lib/thing.zig", .kind = .deleted });

    try testing.expect(!loop.dirty_states[0]);
    try testing.expect(loop.dirty_states[1]);
    try testing.expect(loop.any_dirty);
}

test "flush writes the report and resets the debounce state" {
    const alloc = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = path_buf[0..try tmp.dir.realPathFile(testing.io, ".", &path_buf)];
    const md_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.md" });
    defer alloc.free(md_path);

    var s = testState(alloc, "src", md_path);
    defer deinitTestState(&s, alloc);
    var states = [_]*State{&s};

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    var pool: Pool = .{};
    var watcher: Watcher = undefined;

    var loop = try WatchLoop.init(alloc, testing.io, &cfg, null, &pool, states[0..], null, "zigzag-reports", &watcher);
    defer loop.deinit();

    // Simulate a debounce window that touched one path.
    loop.dirty_states[0] = true;
    loop.any_dirty = true;
    try loop.changed_paths.append(alloc, try alloc.dupe(u8, "src/changed.zig"));

    loop.flush();

    tmp.dir.access(testing.io, "report.md", .{}) catch |err| {
        std.debug.print("expected report.md after flush, got: {s}\n", .{@errorName(err)});
        return err;
    };
    try testing.expect(!loop.dirty_states[0]);
    try testing.expect(!loop.any_dirty);
    try testing.expect(!loop.any_overflow);
    try testing.expectEqual(@as(usize, 0), loop.changed_paths.items.len);
}

test "flush clears the overflow flag after a full rebuild" {
    const alloc = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = path_buf[0..try tmp.dir.realPathFile(testing.io, ".", &path_buf)];
    const md_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.md" });
    defer alloc.free(md_path);

    var s = testState(alloc, "src", md_path);
    defer deinitTestState(&s, alloc);
    var states = [_]*State{&s};

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    var pool: Pool = .{};
    var watcher: Watcher = undefined;

    var loop = try WatchLoop.init(alloc, testing.io, &cfg, null, &pool, states[0..], null, "zigzag-reports", &watcher);
    defer loop.deinit();

    // Overflow path: changed_paths is unreliable, so flush must fall back to a full write.
    loop.any_overflow = true;
    loop.dirty_states[0] = true;
    loop.any_dirty = true;

    loop.flush();

    try testing.expect(!loop.any_overflow);
    try testing.expect(!loop.any_dirty);
    try testing.expect(!loop.dirty_states[0]);
}

test "deinit frees pending changed paths without leaking" {
    const alloc = testing.allocator;
    var s = testState(alloc, "src", "report.md");
    defer deinitTestState(&s, alloc);
    var states = [_]*State{&s};

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    var pool: Pool = .{};
    var watcher: Watcher = undefined;

    var loop = try WatchLoop.init(alloc, testing.io, &cfg, null, &pool, states[0..], null, "zigzag-reports", &watcher);
    // Leave a duplicated path pending; deinit must free it (testing allocator asserts).
    try loop.changed_paths.append(alloc, try alloc.dupe(u8, "src/pending.zig"));
    loop.deinit();
}

test "isIgnoredEventPath filters cache and output-dir events" {
    try testing.expect(WatchLoop.isIgnoredEventPath("proj/.cache/blob", "zigzag-reports"));
    try testing.expect(WatchLoop.isIgnoredEventPath("proj/.zig-cache/o.o", "zigzag-reports"));
    try testing.expect(WatchLoop.isIgnoredEventPath("zigzag-reports/report.md", "zigzag-reports"));
    try testing.expect(WatchLoop.isIgnoredEventPath("src/zigzag-reports/nested.json", "zigzag-reports"));
    try testing.expect(WatchLoop.isIgnoredEventPath("build/out/x", "out"));

    // A real source file must not be filtered and "cache" without the dot is fine.
    try testing.expect(!WatchLoop.isIgnoredEventPath("src/main.zig", "zigzag-reports"));
    try testing.expect(!WatchLoop.isIgnoredEventPath("src/cache_helpers.zig", "zigzag-reports"));
}

test "markAllDirty queues every state for the next flush" {
    const alloc = testing.allocator;
    var s0 = testState(alloc, "src", "a.md");
    defer deinitTestState(&s0, alloc);
    var s1 = testState(alloc, "lib", "b.md");
    defer deinitTestState(&s1, alloc);
    var states = [_]*State{ &s0, &s1 };

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    var pool: Pool = .{};
    var watcher: Watcher = undefined;

    var loop = try WatchLoop.init(alloc, testing.io, &cfg, null, &pool, states[0..], null, "zigzag-reports", &watcher);
    defer loop.deinit();

    loop.markAllDirty();

    try testing.expect(loop.any_dirty);
    for (loop.dirty_states) |d| try testing.expect(d);
}
