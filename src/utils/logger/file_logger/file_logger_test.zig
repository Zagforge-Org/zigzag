const std = @import("std");
const Logger = @import("./file_logger.zig").Logger;

test "Logger.init creates log file in output dir" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    var l = try Logger.init(tmp_path, alloc);
    defer l.deinit();

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

    const content = try tmp.dir.readFileAlloc(alloc, "zigzag.log", 4096);
    defer alloc.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "hello world") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "count 42") != null);
    try std.testing.expect(std.mem.startsWith(u8, content, "["));
}

test "Logger.init appends to existing log file" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    {
        var l = try Logger.init(tmp_path, alloc);
        defer l.deinit();
        l.log("first", .{});
    }
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
