const std = @import("std");
const Config = @import("../../commands/config/config.zig").Config;

pub fn handleLog(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    cfg.log = true;
}
