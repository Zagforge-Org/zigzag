const std = @import("std");
const Config = @import("../../commands/config/config.zig").Config;

/// handleWatch enables watch mode.
pub fn handleWatch(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    cfg.watch = true;
}
