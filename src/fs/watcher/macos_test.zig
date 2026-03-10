const std = @import("std");
const Watcher = @import("./macos.zig").Watcher;
const WatchEvent = @import("./macos.zig").WatchEvent;

test "Watcher.addSkipDir suppresses events from skipped subdirectory" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath(".", &path_buf);

    // Create both subdirs before watching so the snapshot includes them
    try tmp.dir.makeDir("skip_me");
    try tmp.dir.makeDir("keep_me");

    var w = try Watcher.init(alloc);
    defer w.deinit();

    // Register skip before watching
    try w.addSkipDir("skip_me");
    try w.watchDir(path);

    // Create a file in each subdir
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
    for (events.items) |ev| {
        if (std.mem.endsWith(u8, ev.path, "hidden.txt")) saw_skipped = true;
    }
    try std.testing.expect(!saw_skipped);
}

test "Watcher.addSkipDir accepts a full path and extracts basename" {
    const alloc = std.testing.allocator;
    var w = try Watcher.init(alloc);
    defer w.deinit();
    try w.addSkipDir("/some/long/path/to/output-dir");
    try w.addSkipDir("relative/nested/cache");
}

// The macOS kqueue watcher monitors the directory fd with NOTE.WRITE.
// NOTE.WRITE on a directory fd fires when directory entries change (file
// created/deleted/renamed) — NOT when an existing file's content is modified.
// Tests therefore cover "created" and "deleted", which are reliable.

test "Watcher.poll emits created event on new file" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath(".", &path_buf);

    var w = try Watcher.init(alloc);
    defer w.deinit();
    try w.watchDir(path);

    // Create a new file — triggers NOTE.WRITE on the directory fd
    {
        const f = try tmp.dir.createFile("new.txt", .{});
        try f.writeAll("hello");
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
        if (std.mem.endsWith(u8, ev.path, "new.txt") and ev.kind == .created)
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
