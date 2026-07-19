const std = @import("std");

/// Check if path exists
pub fn exists(io: std.Io, path: []const u8) !bool {
    std.Io.Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}
