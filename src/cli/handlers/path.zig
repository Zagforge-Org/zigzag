const std = @import("std");
const testing = std.testing;

const Config = @import("../commands/config/config.zig").Config;
const makeTestConfig = @import("./test_config.zig").makeTestConfig;

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

test "handlePaths single path" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();
    try handlePaths(&cfg, allocator, "path");
    try testing.expectEqual(@as(usize, 1), cfg.paths.items.len);
    try testing.expectEqualStrings("path", cfg.paths.items[0]);
}

test "handlePaths comma-separated paths" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();
    try handlePaths(&cfg, allocator, "./src,./lib,./test");
    try testing.expectEqual(@as(usize, 3), cfg.paths.items.len);
    try testing.expectEqualStrings("./src", cfg.paths.items[0]);
    try testing.expectEqualStrings("./lib", cfg.paths.items[1]);
    try testing.expectEqualStrings("./test", cfg.paths.items[2]);
}

test "handlePaths trims whitespace from segments" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();
    try handlePaths(&cfg, allocator, "./src, ./lib , ./test");
    try testing.expectEqual(@as(usize, 3), cfg.paths.items.len);
    try testing.expectEqualStrings("./src", cfg.paths.items[0]);
    try testing.expectEqualStrings("./lib", cfg.paths.items[1]);
    try testing.expectEqualStrings("./test", cfg.paths.items[2]);
}

test "handlePaths skips empty segments" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();
    try handlePaths(&cfg, allocator, "./src,,./lib");
    try testing.expectEqual(@as(usize, 2), cfg.paths.items.len);
    try testing.expectEqualStrings("./src", cfg.paths.items[0]);
    try testing.expectEqualStrings("./lib", cfg.paths.items[1]);
}

test "handlePaths multiple calls accumulate" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();
    try handlePaths(&cfg, allocator, "./src,./lib");
    try handlePaths(&cfg, allocator, "./test");
    try testing.expectEqual(@as(usize, 3), cfg.paths.items.len);
    try testing.expectEqualStrings("./src", cfg.paths.items[0]);
    try testing.expectEqualStrings("./lib", cfg.paths.items[1]);
    try testing.expectEqualStrings("./test", cfg.paths.items[2]);
}

test "handlePaths first call clears file-loaded paths" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    // Simulate file-loaded path
    const file_path = try allocator.dupe(u8, "./from_file");
    try cfg.paths.append(allocator, file_path);

    // First CLI --path should replace file paths
    try handlePaths(&cfg, allocator, "./from_cli");
    try testing.expectEqual(@as(usize, 1), cfg.paths.items.len);
    try testing.expectEqualStrings("./from_cli", cfg.paths.items[0]);
}

test "handlePaths null value is a no-op" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();
    try handlePaths(&cfg, allocator, null);
    try testing.expectEqual(@as(usize, 0), cfg.paths.items.len);
}
