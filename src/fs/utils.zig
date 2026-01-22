const std = @import("std");

/// Check if path exists
pub fn exists(path: []const u8) !bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}
