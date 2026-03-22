const std = @import("std");
const Config = @import("../../commands/config/config.zig").Config;

/// handleMmap handles the mmap option.
pub fn handleMmap(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    if (value) |v| {
        cfg.mmap_threshold = try std.fmt.parseInt(usize, v, 10);
    }
}
