const std = @import("std");
const Config = @import("../../commands/config/config.zig").Config;

/// handlePaths handles the path option (can be called multiple times).
/// Accepts comma-separated paths; whitespace around each segment is trimmed.
/// When called via CLI, the first invocation replaces any file-config paths.
pub fn handlePaths(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    if (value) |raw| {
        // First CLI --path call: replace file-loaded paths (CLI overrides file config)
        if (!cfg._paths_set_by_cli) {
            cfg._paths_set_by_cli = true;
            for (cfg.paths.items) |p| allocator.free(p);
            cfg.paths.clearRetainingCapacity();
        }

        var it = std.mem.splitScalar(u8, raw, ',');
        while (it.next()) |segment| {
            const path = std.mem.trim(u8, segment, &std.ascii.whitespace);
            if (path.len == 0) continue;
            const owned_path = try allocator.dupe(u8, path);
            try cfg.paths.append(allocator, owned_path);
        }
    }
}
