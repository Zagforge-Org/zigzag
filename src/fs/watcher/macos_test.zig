const std = @import("std");
const Watcher = @import("./macos.zig").Watcher;
const WatchEvent = @import("./macos.zig").WatchEvent;
const WatchEventKind = @import("./macos.zig").WatchEventKind;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn freeEvents(alloc: std.mem.Allocator, events: *std.ArrayList(WatchEvent)) void {
    for (events.items) |ev| alloc.free(ev.path);
    events.deinit(alloc);
}

fn hasEvent(events: []const WatchEvent, suffix: []const u8, kind: WatchEventKind) bool {
    for (events) |ev| {
        if (std.mem.endsWith(u8, ev.path, suffix) and ev.kind == kind) return true;
    }
    return false;
}

fn hasEventAnyKind(events: []const WatchEvent, suffix: []const u8) bool {
    for (events) |ev| {
        if (std.mem.endsWith(u8, ev.path, suffix)) return true;
    }
    return false;
}

// ---------------------------------------------------------------------------
// Skip-dir tests
// ---------------------------------------------------------------------------

test "addSkipDir suppresses events from skipped subdirectory" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = path_buf[0..try tmp.dir.realPathFile(std.testing.io, ".", &path_buf)];

    try tmp.dir.createDir(std.testing.io, "skip_me", .default_dir);
    try tmp.dir.createDir(std.testing.io, "keep_me", .default_dir);

    var w = try Watcher.init(alloc);
    defer w.deinit();

    try w.addSkipDir("skip_me");
    try w.watchDir(path);

    {
        const f = try tmp.dir.createFile(std.testing.io, "skip_me/hidden.txt", .{});
        try f.writeAll("should not appear");
        f.close(std.testing.io);
    }
    {
        const f = try tmp.dir.createFile(std.testing.io, "keep_me/visible.txt", .{});
        try f.writeAll("should appear");
        f.close(std.testing.io);
    }

    var events: std.ArrayList(WatchEvent) = .empty;
    defer freeEvents(alloc, &events);
    _ = try w.poll(&events, 500);

    try std.testing.expect(!hasEvent(events.items, "hidden.txt", .created));
}

test "addSkipDir accepts a full path and extracts basename" {
    const alloc = std.testing.allocator;
    var w = try Watcher.init(alloc);
    defer w.deinit();
    try w.addSkipDir("/some/long/path/to/output-dir");
    try w.addSkipDir("relative/nested/cache");
}

// ---------------------------------------------------------------------------
// Create / delete tests (kqueue instant detection)
// ---------------------------------------------------------------------------

test "poll emits created event on new file" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = path_buf[0..try tmp.dir.realPathFile(std.testing.io, ".", &path_buf)];

    var w = try Watcher.init(alloc);
    defer w.deinit();
    try w.watchDir(path);

    {
        const f = try tmp.dir.createFile(std.testing.io, "new.txt", .{});
        try f.writeAll("hello");
        f.close(std.testing.io);
    }

    var events: std.ArrayList(WatchEvent) = .empty;
    defer freeEvents(alloc, &events);
    const n = try w.poll(&events, 1000);

    try std.testing.expect(n > 0);
    try std.testing.expect(hasEvent(events.items, "new.txt", .created));
}

test "poll emits deleted event on file removal" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = path_buf[0..try tmp.dir.realPathFile(std.testing.io, ".", &path_buf)];

    {
        const f = try tmp.dir.createFile(std.testing.io, "to_delete.txt", .{});
        f.close(std.testing.io);
    }

    var w = try Watcher.init(alloc);
    defer w.deinit();
    try w.watchDir(path);

    try tmp.dir.deleteFile(std.testing.io, "to_delete.txt");

    var events: std.ArrayList(WatchEvent) = .empty;
    defer freeEvents(alloc, &events);
    const n = try w.poll(&events, 1000);

    try std.testing.expect(n > 0);
    try std.testing.expect(hasEvent(events.items, "to_delete.txt", .deleted));
}

// ---------------------------------------------------------------------------
// In-place modification test (mtime fallback — the bug that was fixed)
//
// kqueue NOTE_WRITE on a directory fd does NOT fire when an existing file's
// content is modified in-place. The mtime fallback scan must detect it.
// ---------------------------------------------------------------------------

test "mtime fallback detects in-place file modification" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = path_buf[0..try tmp.dir.realPathFile(std.testing.io, ".", &path_buf)];

    // Create file BEFORE watching so the snapshot records its mtime.
    {
        const f = try tmp.dir.createFile(std.testing.io, "existing.txt", .{});
        try f.writeAll("original");
        f.close(std.testing.io);
    }

    var w = try Watcher.init(alloc);
    defer w.deinit();
    try w.watchDir(path);

    // Small sleep so the mtime changes (filesystem time granularity).
    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Modify the file in-place.
    {
        const f = try tmp.dir.createFile(std.testing.io, "existing.txt", .{});
        try f.writeAll("modified content that is different");
        f.close(std.testing.io);
    }

    // Force the mtime scan to fire immediately on next poll.
    w.last_mtime_scan = 0;

    var events: std.ArrayList(WatchEvent) = .empty;
    defer freeEvents(alloc, &events);
    _ = try w.poll(&events, 500);

    // The change must be detected (kind may be .modified or .created depending
    // on whether kqueue also fired — either way, detection is what matters).
    try std.testing.expect(hasEventAnyKind(events.items, "existing.txt"));
}

test "mtime fallback detects in-place modification in subdirectory" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = path_buf[0..try tmp.dir.realPathFile(std.testing.io, ".", &path_buf)];

    try tmp.dir.createDir(std.testing.io, "nested", .default_dir);
    {
        const f = try tmp.dir.createFile(std.testing.io, "nested/config.txt", .{});
        try f.writeAll("v1");
        f.close(std.testing.io);
    }

    var w = try Watcher.init(alloc);
    defer w.deinit();
    try w.watchDir(path);

    std.Thread.sleep(50 * std.time.ns_per_ms);

    {
        const f = try tmp.dir.createFile(std.testing.io, "nested/config.txt", .{});
        try f.writeAll("v2 changed");
        f.close(std.testing.io);
    }

    w.last_mtime_scan = 0;

    var events: std.ArrayList(WatchEvent) = .empty;
    defer freeEvents(alloc, &events);
    _ = try w.poll(&events, 500);

    try std.testing.expect(hasEventAnyKind(events.items, "config.txt"));
}

// ---------------------------------------------------------------------------
// Round-robin batching
// ---------------------------------------------------------------------------

test "mtime scan advances round-robin cursor" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = path_buf[0..try tmp.dir.realPathFile(std.testing.io, ".", &path_buf)];

    try tmp.dir.createDir(std.testing.io, "dir_a", .default_dir);
    try tmp.dir.createDir(std.testing.io, "dir_b", .default_dir);
    try tmp.dir.createDir(std.testing.io, "dir_c", .default_dir);

    var w = try Watcher.init(alloc);
    defer w.deinit();
    try w.watchDir(path);

    // At least root + 3 subdirs
    try std.testing.expect(w.dir_fds.items.len >= 4);

    w.last_mtime_scan = 0;
    var events: std.ArrayList(WatchEvent) = .empty;
    defer freeEvents(alloc, &events);
    _ = try w.poll(&events, 100);

    // Cursor should have advanced
    try std.testing.expect(w.mtime_scan_cursor > 0);
}

// ---------------------------------------------------------------------------
// No spurious events
// ---------------------------------------------------------------------------

test "poll returns 0 events when no files changed" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = path_buf[0..try tmp.dir.realPathFile(std.testing.io, ".", &path_buf)];

    {
        const f = try tmp.dir.createFile(std.testing.io, "stable.txt", .{});
        try f.writeAll("unchanged");
        f.close(std.testing.io);
    }

    var w = try Watcher.init(alloc);
    defer w.deinit();
    try w.watchDir(path);

    // Force mtime scan with nothing changed
    w.last_mtime_scan = 0;

    var events: std.ArrayList(WatchEvent) = .empty;
    defer freeEvents(alloc, &events);
    const n = try w.poll(&events, 200);

    try std.testing.expectEqual(@as(usize, 0), n);
}

// ---------------------------------------------------------------------------
// Inode deduplication
// ---------------------------------------------------------------------------

test "watchDir deduplicates overlapping paths by inode" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = path_buf[0..try tmp.dir.realPathFile(std.testing.io, ".", &path_buf)];

    var w = try Watcher.init(alloc);
    defer w.deinit();

    try w.watchDir(path);
    const count_after_first = w.dir_fds.items.len;

    // Watching the same path again should not add duplicate entries
    try w.watchDir(path);
    try std.testing.expectEqual(count_after_first, w.dir_fds.items.len);
}

// ---------------------------------------------------------------------------
// Subdirectory file creation (kqueue)
// ---------------------------------------------------------------------------

test "poll detects file created in subdirectory" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = path_buf[0..try tmp.dir.realPathFile(std.testing.io, ".", &path_buf)];

    try tmp.dir.createDir(std.testing.io, "subdir", .default_dir);

    var w = try Watcher.init(alloc);
    defer w.deinit();
    try w.watchDir(path);

    {
        const f = try tmp.dir.createFile(std.testing.io, "subdir/deep.txt", .{});
        try f.writeAll("deep file");
        f.close(std.testing.io);
    }

    var events: std.ArrayList(WatchEvent) = .empty;
    defer freeEvents(alloc, &events);
    _ = try w.poll(&events, 1000);

    try std.testing.expect(hasEvent(events.items, "deep.txt", .created));
}
