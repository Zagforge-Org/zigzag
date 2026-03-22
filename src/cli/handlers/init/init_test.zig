const std = @import("std");
const testing = std.testing;
const handleInit = @import("./init.zig").handleInit;
const FileConf = @import("../../../conf/file.zig").FileConf;
const DEFAULT_CONF_FILENAME = @import("../../../conf/file.zig").DEFAULT_CONF_FILENAME;

test "handleInit creates file with default content" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try handleInit(allocator, tmp_dir.dir);

    // Verify file was created with valid default JSON
    const content = try tmp_dir.dir.readFileAlloc(allocator, DEFAULT_CONF_FILENAME, 1 << 20);
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
        const f = try tmp_dir.dir.createFile(DEFAULT_CONF_FILENAME, .{});
        defer f.close();
        try f.writeAll("{\"watch\": true}");
    }

    // handleInit should not overwrite
    try handleInit(allocator, tmp_dir.dir);

    const content = try tmp_dir.dir.readFileAlloc(allocator, DEFAULT_CONF_FILENAME, 1 << 20);
    defer allocator.free(content);

    try testing.expectEqualStrings("{\"watch\": true}", content);
}
