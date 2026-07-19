const std = @import("std");
const Config = @import("../../commands/config/config.zig").Config;

/// handleSkipCache handles the skip-cache option.
pub fn handleSkipCache(_: std.Io, cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    cfg.skip_cache = true;
}
