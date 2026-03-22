const std = @import("std");
const Config = @import("../../commands/config/config.zig").Config;

pub fn handleUpload(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    cfg.upload = true;
}
