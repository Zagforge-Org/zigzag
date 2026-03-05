const std = @import("std");
const testing = std.testing;
const fs = std.fs;

const DEFAULT_CONF_FILENAME = @import("../../conf/file.zig").DEFAULT_CONF_FILENAME;
const defaultContent = @import("../../conf/file.zig").defaultContent;

/// handleInit creates the zig.conf.json configuration file with default values.
/// dir is the directory in which to create the file (use std.fs.cwd() for normal use).
pub fn handleInit(allocator: std.mem.Allocator, dir: std.fs.Dir) anyerror!void {
    _ = allocator;

    const file = dir.createFile(DEFAULT_CONF_FILENAME, .{
        .read = true,
        .exclusive = true,
    }) catch |err| switch (err) {
        error.PathAlreadyExists => {
            std.log.info("zigzag: {s} already exists", .{DEFAULT_CONF_FILENAME});
            return;
        },
        else => return err,
    };
    defer file.close();

    try file.writeAll(defaultContent());
    std.log.info("zigzag: created {s}", .{DEFAULT_CONF_FILENAME});
}

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
        @import("../../conf/file.zig").FileConf,
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
