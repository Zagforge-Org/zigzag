const std = @import("std");

/// Check if path exists
pub fn exists(path: []const u8) !bool {
    std.Io.Dir.cwd().access(path, .{}) catch return false;
    return true;
}
