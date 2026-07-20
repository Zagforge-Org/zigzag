const std = @import("std");
const Config = @import("../../commands/config/Config.zig");

/// handleMmap handles the mmap option.
pub fn handleMmap(_: std.Io, cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    if (value) |v| {
        cfg.mmap_threshold = try std.fmt.parseInt(usize, v, 10);
    }
}
