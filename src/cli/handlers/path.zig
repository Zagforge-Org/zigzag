const std = @import("std");
const testing = std.testing;

const Config = @import("../commands/config/config.zig").Config;
const makeTestConfig = @import("./test_config.zig").makeTestConfig;

/// handlePath handles the path option (can be called multiple times).
/// When called via CLI, the first invocation replaces any file-config paths.
pub fn handlePath(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    if (value) |path| {
        // First CLI --path call: replace file-loaded paths (CLI overrides file config)
        if (!cfg._paths_set_by_cli) {
            cfg._paths_set_by_cli = true;
            for (cfg.paths.items) |p| allocator.free(p);
            cfg.paths.clearRetainingCapacity();
        }

        const owned_path = try allocator.dupe(u8, path);
        try cfg.paths.append(allocator, owned_path);
    }
}

test "handlePath handles path option" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();
    try handlePath(&cfg, allocator, "path");
    try testing.expectEqualStrings("path", cfg.paths.items[0]);
}

test "handlePath accumulates multiple paths" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handlePath(&cfg, allocator, "./src");
    try handlePath(&cfg, allocator, "./lib");
    try testing.expectEqual(@as(usize, 2), cfg.paths.items.len);
    try testing.expectEqualStrings("./src", cfg.paths.items[0]);
    try testing.expectEqualStrings("./lib", cfg.paths.items[1]);
}

test "handlePath CLI overrides file-loaded paths" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    // Simulate file-loaded path
    const file_path = try allocator.dupe(u8, "./from_file");
    try cfg.paths.append(allocator, file_path);

    // First CLI --path should replace file paths
    try handlePath(&cfg, allocator, "./from_cli");
    try testing.expectEqual(@as(usize, 1), cfg.paths.items.len);
    try testing.expectEqualStrings("./from_cli", cfg.paths.items[0]);

    // Second CLI --path accumulates
    try handlePath(&cfg, allocator, "./also_cli");
    try testing.expectEqual(@as(usize, 2), cfg.paths.items.len);
}
