const std = @import("std");
const Config = @import("../../commands/config/config.zig").Config;

/// handleOutputDir sets the base output directory for generated reports.
pub fn handleOutputDir(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    if (value) |v| {
        const trimmed = std.mem.trim(u8, v, " \t\r\n");
        if (trimmed.len == 0) return;
        if (cfg._output_dir_allocated) {
            if (cfg.output_dir) |existing| allocator.free(existing);
        }
        cfg.output_dir = try allocator.dupe(u8, trimmed);
        cfg._output_dir_allocated = true;
        cfg._output_dir_set_by_cli = true;
    }
}
