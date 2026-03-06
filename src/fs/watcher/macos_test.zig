const std = @import("std");
const Watcher = @import("./macos.zig").Watcher;
const WatchEvent = @import("./macos.zig").WatchEvent;

test "Watcher.poll emits modified event on file write" {
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

    // Open, write, close — triggers kqueue NOTE.WRITE on directory → snapshot diff → .modified
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
