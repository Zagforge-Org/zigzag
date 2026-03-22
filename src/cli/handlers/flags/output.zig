const std = @import("std");
const Config = @import("../../commands/config/config.zig").Config;

/// handleOutput sets the output filename for the generated report.
pub fn handleOutput(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    if (value) |filename| {
        const trimmed = std.mem.trim(u8, filename, " \t\n\r");
        if (trimmed.len == 0) return;

        if (cfg.output) |existing| allocator.free(existing);
        cfg.output = try allocator.dupe(u8, trimmed);
    }
}
