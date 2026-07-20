const std = @import("std");
const Config = @import("../../commands/config/Config.zig");

/// handleSmall handles the small option.
pub fn handleSmall(_: std.Io, cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    if (value) |v| {
        cfg.small_threshold = try std.fmt.parseInt(usize, v, 10);
    }
}
