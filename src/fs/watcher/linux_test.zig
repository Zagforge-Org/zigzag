const std = @import("std");
const Watcher = @import("./linux.zig").Watcher;
const WatchEvent = @import("./linux.zig").WatchEvent;

test "Watcher.addSkipDir suppresses events from skipped subdirectory" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath(".", &path_buf);

    // Create a subdirectory that will be skipped
    try tmp.dir.makeDir("skip_me");
    try tmp.dir.makeDir("keep_me");

    var w = try Watcher.init(alloc);
    defer w.deinit();

    // Register skip before watching
    try w.addSkipDir("skip_me");
    try w.watchDir(path);

    // Write inside the skipped subdir and the non-skipped subdir
    {
        const f = try tmp.dir.createFile("skip_me/hidden.txt", .{});
        try f.writeAll("should not appear");
        f.close();
    }
    {
        const f = try tmp.dir.createFile("keep_me/visible.txt", .{});
        try f.writeAll("should appear");
        f.close();
    }

    var events: std.ArrayList(WatchEvent) = .empty;
    defer {
        for (events.items) |ev| alloc.free(ev.path);
        events.deinit(alloc);
    }
    _ = try w.poll(&events, 500);

    var saw_skipped = false;
    var saw_visible = false;
    for (events.items) |ev| {
        if (std.mem.endsWith(u8, ev.path, "hidden.txt")) saw_skipped = true;
        if (std.mem.endsWith(u8, ev.path, "visible.txt")) saw_visible = true;
    }
    try std.testing.expect(!saw_skipped);
    try std.testing.expect(saw_visible);
}

test "Watcher.addSkipDir accepts a full path and extracts basename" {
    const alloc = std.testing.allocator;
    var w = try Watcher.init(alloc);
    defer w.deinit();
    // Should not error; basename extraction must handle full paths
    try w.addSkipDir("/some/long/path/to/output-dir");
    try w.addSkipDir("relative/nested/cache");
}

test "Watcher.poll emits modified event on CLOSE_WRITE" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath(".", &path_buf);

    // Create file before watching so its creation doesn't pollute events
    {
        const f = try tmp.dir.createFile("existing.txt", .{});
        f.close();
    }

    var w = try Watcher.init(alloc);
    defer w.deinit();
    try w.watchDir(path);

    // Open, write, close — triggers IN_CLOSE_WRITE → .modified
    {
        const f = try tmp.dir.openFile("existing.txt", .{ .mode = .write_only });
        try f.writeAll("new content");
        f.close();
    }

    var events: std.ArrayList(WatchEvent) = .empty;
    defer {
        for (events.items) |ev| alloc.free(ev.path);
        events.deinit(alloc);
    }
    const n = try w.poll(&events, 500);
    try std.testing.expect(n > 0);

    var found = false;
    for (events.items) |ev| {
        if (std.mem.endsWith(u8, ev.path, "existing.txt") and ev.kind == .modified)
            found = true;
    }
    try std.testing.expect(found);
}

test "Watcher.poll emits deleted event on file removal" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath(".", &path_buf);

    {
        const f = try tmp.dir.createFile("to_delete.txt", .{});
        f.close();
    }

    var w = try Watcher.init(alloc);
    defer w.deinit();
    try w.watchDir(path);

    try tmp.dir.deleteFile("to_delete.txt");

    var events: std.ArrayList(WatchEvent) = .empty;
    defer {
        for (events.items) |ev| alloc.free(ev.path);
        events.deinit(alloc);
    }
    const n = try w.poll(&events, 500);
    try std.testing.expect(n > 0);

    var found = false;
    for (events.items) |ev| {
        if (std.mem.endsWith(u8, ev.path, "to_delete.txt") and ev.kind == .deleted)
            found = true;
    }
    try std.testing.expect(found);
}
