const std = @import("std");
const Config = @import("../../commands/config/Config.zig");

/// handleOpen sets the open_browser flag so serve/watch opens the browser on start.
pub fn handleOpen(_: std.Io, cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    cfg.open_browser = true;
}
