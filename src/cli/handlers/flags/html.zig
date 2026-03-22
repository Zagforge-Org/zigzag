const std = @import("std");
const Config = @import("../../commands/config/config.zig").Config;

/// handleHtml enables HTML report output alongside the markdown report.
pub fn handleHtml(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    cfg.html_output = true;
}
