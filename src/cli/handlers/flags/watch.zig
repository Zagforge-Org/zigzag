const std = @import("std");
const Config = @import("../../commands/config/Config.zig");

/// handleWatch enables watch mode.
pub fn handleWatch(_: std.Io, cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    cfg.watch = true;
}
