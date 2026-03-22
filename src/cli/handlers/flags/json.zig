const std = @import("std");
const Config = @import("../../commands/config/config.zig").Config;

/// handleJson enables JSON report output alongside the markdown report.
pub fn handleJson(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    cfg.json_output = true;
}
