const std = @import("std");
const testing = std.testing;
const handleInit = @import("./init.zig").handleInit;
const FileConf = @import("../../../conf/FileConf.zig");
const DEFAULT_CONF_FILE = @import("../../../conf/FileConf.zig").DEFAULT_CONF_FILE;

test "handleInit creates file with default content" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try handleInit(std.testing.io, allocator, tmp_dir.dir);

    // Verify file was created with valid default JSON
    const content = try tmp_dir.dir.readFileAlloc(std.testing.io, DEFAULT_CONF_FILE, allocator, .limited(1 << 20));
    defer allocator.free(content);

    try testing.expect(content.len > 0);

    const parsed = try std.json.parseFromSlice(
        FileConf,
        allocator,
        content,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    try testing.expect(parsed.value.watch.? == false);
    try testing.expectEqualStrings("report.md", parsed.value.output.?);
}

test "handleInit does not overwrite existing file" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create the file with custom content first
    {
        const f = try tmp_dir.dir.createFile(std.testing.io, DEFAULT_CONF_FILE, .{});
        defer f.close(std.testing.io);
        try f.writeStreamingAll(std.testing.io, "{\"watch\": true}");
    }

    // handleInit should not overwrite
    try handleInit(std.testing.io, allocator, tmp_dir.dir);

    const content = try tmp_dir.dir.readFileAlloc(std.testing.io, DEFAULT_CONF_FILE, allocator, .limited(1 << 20));
    defer allocator.free(content);

    try testing.expectEqualStrings("{\"watch\": true}", content);
}
