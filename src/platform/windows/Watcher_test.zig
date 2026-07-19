const std = @import("std");
const Watcher = @import("./Watcher.zig");
const WatchEvent = @import("./Watcher.zig").WatchEvent;

test "Watcher.addSkipDir suppresses events from skipped subdirectory" {
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
    // Let the background thread start and enter ReadDirectoryChangesW
    std.Io.sleep(std.testing.io, .fromNanoseconds(100 * std.time.ns_per_ms), .awake) catch {};

    {
        const f = try tmp.dir.createFile(std.testing.io, "skip_me\\hidden.txt", .{});
        try f.writeStreamingAll(std.testing.io, "should not appear");
        f.close(std.testing.io);
    }
    {
        const f = try tmp.dir.createFile(std.testing.io, "keep_me\\visible.txt", .{});
        try f.writeStreamingAll(std.testing.io, "should appear");
        f.close(std.testing.io);
    }

    std.Io.sleep(std.testing.io, .fromNanoseconds(100 * std.time.ns_per_ms), .awake) catch {};

    var events: std.ArrayList(WatchEvent) = .empty;
    defer {
        for (events.items) |ev| alloc.free(ev.path);
        events.deinit(alloc);
    }
    _ = try w.poll(&events, 1000);

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
    try w.addSkipDir("C:\\some\\path\\output-dir");
    try w.addSkipDir("relative\\nested\\cache");
}

test "Watcher.poll emits modified event on file write" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = path_buf[0..try tmp.dir.realPathFile(std.testing.io, ".", &path_buf)];

    // Create file before watching so its creation doesn't pollute events
    {
        const f = try tmp.dir.createFile(std.testing.io, "existing.txt", .{});
        f.close(std.testing.io);
    }

    var w = try Watcher.init(alloc);
    defer w.deinit();
    try w.watchDir(path);
    // Let the background thread start and enter ReadDirectoryChangesW
    std.Io.sleep(std.testing.io, .fromNanoseconds(100 * std.time.ns_per_ms), .awake) catch {};

    // Open, write, close: background thread picks up ReadDirectoryChangesW event
    {
        const f = try tmp.dir.openFile(std.testing.io, "existing.txt", .{ .mode = .write_only });
        try f.writeStreamingAll(std.testing.io, "new content");
        f.close(std.testing.io);
    }

    // Give the background thread time to receive and enqueue the event
    std.Io.sleep(std.testing.io, .fromNanoseconds(100 * std.time.ns_per_ms), .awake) catch {};

    var events: std.ArrayList(WatchEvent) = .empty;
    defer {
        for (events.items) |ev| alloc.free(ev.path);
        events.deinit(alloc);
    }
    const n = try w.poll(&events, 1000);
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
    const path = path_buf[0..try tmp.dir.realPathFile(std.testing.io, ".", &path_buf)];

    {
        const f = try tmp.dir.createFile(std.testing.io, "to_delete.txt", .{});
        f.close(std.testing.io);
    }

    var w = try Watcher.init(alloc);
    defer w.deinit();
    try w.watchDir(path);
    // Let the background thread start and enter ReadDirectoryChangesW
    std.Io.sleep(std.testing.io, .fromNanoseconds(100 * std.time.ns_per_ms), .awake) catch {};

    try tmp.dir.deleteFile(std.testing.io, "to_delete.txt");

    // Give the background thread time to receive and enqueue the event
    std.Io.sleep(std.testing.io, .fromNanoseconds(100 * std.time.ns_per_ms), .awake) catch {};

    var events: std.ArrayList(WatchEvent) = .empty;
    defer {
        for (events.items) |ev| alloc.free(ev.path);
        events.deinit(alloc);
    }
    const n = try w.poll(&events, 1000);
    try std.testing.expect(n > 0);

    var found = false;
    for (events.items) |ev| {
        if (std.mem.endsWith(u8, ev.path, "to_delete.txt") and ev.kind == .deleted)
            found = true;
    }
    try std.testing.expect(found);
}
