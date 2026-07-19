const std = @import("std");
const Config = @import("../../commands/config/Config.zig");

/// handleHtml enables HTML report output alongside the markdown report.
pub fn handleHtml(_: std.Io, cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    cfg.html_output = true;
}
