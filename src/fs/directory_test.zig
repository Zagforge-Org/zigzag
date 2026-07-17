const std = @import("std");
const isDirectory = @import("directory.zig").isDirectory;

test "isDirectory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(tmp_path);

    // Test a directory
    try tmp.dir.makeDir(std.testing.io, "subdir");
    const subdir_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_path, "subdir" });
    defer std.testing.allocator.free(subdir_path);
    try std.testing.expectEqual(true, try isDirectory(subdir_path));

    // Test a file
    _ = try tmp.dir.createFile(std.testing.io, "file.txt", .{});
    const file_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_path, "file.txt" });
    defer std.testing.allocator.free(file_path);
    try std.testing.expectEqual(false, try isDirectory(file_path));

    // Test a non-existent path
    const non_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_path, "nonexistent" });
    defer std.testing.allocator.free(non_path);
    try std.testing.expectError(error.FileNotFound, isDirectory(non_path));
}
