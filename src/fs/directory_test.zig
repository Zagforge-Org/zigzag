const std = @import("std");
const isDirectory = @import("directory.zig").isDirectory;

test "isDirectory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(tmp_path);

    // Test a directory
    try tmp.dir.createDir(std.testing.io, "subdir", .default_dir);
    const subdir_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_path, "subdir" });
    defer std.testing.allocator.free(subdir_path);
    try std.testing.expectEqual(true, try isDirectory(std.testing.io, subdir_path));

    // Test a file
    _ = try tmp.dir.createFile(std.testing.io, "file.txt", .{});
    const file_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_path, "file.txt" });
    defer std.testing.allocator.free(file_path);
    try std.testing.expectEqual(false, try isDirectory(std.testing.io, file_path));

    // Test a non-existent path
    const non_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_path, "nonexistent" });
    defer std.testing.allocator.free(non_path);
    try std.testing.expectError(error.FileNotFound, isDirectory(std.testing.io, non_path));
}
