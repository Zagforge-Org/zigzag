const std = @import("std");

/// isDirectory checks if path is a directory
pub fn isDirectory(path: []const u8) !bool {
    const stat = try std.fs.cwd().statFile(path);
    return stat.kind == .directory;
}
