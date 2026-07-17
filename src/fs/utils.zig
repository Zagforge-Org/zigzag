const std = @import("std");
const rt = @import("../runtime.zig");

/// Check if path exists
pub fn exists(path: []const u8) !bool {
    std.Io.Dir.cwd().access(rt.io(), path, .{}) catch return false;
    return true;
}
