const std = @import("std");
const logger = @import("./logger.zig");
const Logger = logger.Logger;

test "Logger.init creates log file in output dir" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    var l = try Logger.init(tmp_path, alloc);
    defer l.deinit();

    // File should exist
    const stat = try tmp.dir.statFile("zigzag.log");
    try std.testing.expect(stat.kind == .file);
}

test "Logger.log writes timestamped entry to file" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    {
        var l = try Logger.init(tmp_path, alloc);
        defer l.deinit();
        l.log("hello {s}", .{"world"});
        l.log("count {d}", .{42});
    }

    // Read back and verify content
    const content = try tmp.dir.readFileAlloc(alloc, "zigzag.log", 4096);
    defer alloc.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "hello world") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "count 42") != null);
    // Each line should start with a bracketed timestamp
    try std.testing.expect(std.mem.startsWith(u8, content, "["));
}

test "Logger.init appends to existing log file" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    // First session
    {
        var l = try Logger.init(tmp_path, alloc);
        defer l.deinit();
        l.log("first", .{});
    }

    // Second session — must append, not truncate
    {
        var l = try Logger.init(tmp_path, alloc);
        defer l.deinit();
        l.log("second", .{});
    }

    const content = try tmp.dir.readFileAlloc(alloc, "zigzag.log", 4096);
    defer alloc.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "first") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "second") != null);
}

test "printStep does not panic" {
    logger.printStep("test step {s}", .{"ok"});
}

test "printSuccess does not panic" {
    logger.printSuccess("done {d}", .{1});
}

test "printError does not panic" {
    logger.printError("failed {s}", .{"reason"});
}

test "printWarn does not panic" {
    logger.printWarn("warning {s}", .{"msg"});
}

test "printSummary does not panic" {
    logger.printSummary("./src", 10, 8, 5, 3, 1, 1);
}
