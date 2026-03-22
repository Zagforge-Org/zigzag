const std = @import("std");
const Config = @import("../../commands/config/config.zig").Config;

/// handleIgnores handles the ignore option - can be called multiple times.
/// Accepts comma-separated patterns in a single value.
/// When called via CLI, the first invocation replaces any file-config patterns.
/// Subsequent CLI invocations accumulate additional patterns.
pub fn handleIgnores(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    if (value) |raw| {
        // First CLI --ignore call: replace file-loaded patterns (CLI overrides file config)
        if (!cfg._patterns_set_by_cli) {
            cfg._patterns_set_by_cli = true;
            cfg.clearIgnorePatterns();
        }

        var it = std.mem.splitScalar(u8, raw, ',');
        while (it.next()) |segment| {
            const trimmed = std.mem.trim(u8, segment, &std.ascii.whitespace);
            if (trimmed.len == 0) continue;
            try cfg.appendIgnorePattern(trimmed);
        }
    }
}
