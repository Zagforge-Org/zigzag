const std = @import("std");
const Config = @import("../../commands/config/config.zig").Config;

/// handlePort sets the SSE/HTML dev server port (used in --watch --html mode).
pub fn handlePort(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    const v = value orelse return error.MissingValue;
    const port = std.fmt.parseInt(u16, v, 10) catch return error.InvalidPort;
    cfg.serve_port = port;
}
