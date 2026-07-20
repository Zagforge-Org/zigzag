const std = @import("std");
const Config = @import("../../commands/config/Config.zig");

pub fn handleLog(_: std.Io, cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    cfg.log = true;
}
