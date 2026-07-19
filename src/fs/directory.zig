const std = @import("std");

/// isDirectory checks if path is a directory
pub fn isDirectory(io: std.Io, path: []const u8) !bool {
    const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch |err| switch (err) {
        // on Windows statFile opens the path as a file and the OS rejects
        // directories with FILE_IS_A_DIRECTORY, so IsDir means it is one.
        error.IsDir => return true,
        else => return err,
    };
    return stat.kind == .directory;
}
