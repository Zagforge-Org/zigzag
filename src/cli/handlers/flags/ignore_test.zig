const std = @import("std");
const testing = std.testing;
const handleIgnores = @import("./ignore.zig").handleIgnores;
const makeTestConfig = @import("../internal/test_config.zig").makeTestConfig;

fn hasPattern(patterns: std.ArrayList([]const u8), needle: []const u8) bool {
    for (patterns.items) |p| {
        if (std.mem.eql(u8, p, needle)) return true;
    }
    return false;
}

test "handleIgnores single pattern" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleIgnores(&cfg, allocator, "*.png");
    try testing.expect(hasPattern(cfg.ignore_patterns, "*.png"));
}

test "handleIgnores comma-separated patterns" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleIgnores(&cfg, allocator, "*.png,*.jpg");
    try testing.expect(hasPattern(cfg.ignore_patterns, "*.png"));
    try testing.expect(hasPattern(cfg.ignore_patterns, "*.jpg"));
    try testing.expectEqual(@as(usize, 2), cfg.ignore_patterns.items.len);
}

test "handleIgnores trims whitespace from segments" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleIgnores(&cfg, allocator, "*.png, *.jpg , *.gif");
    try testing.expect(hasPattern(cfg.ignore_patterns, "*.png"));
    try testing.expect(hasPattern(cfg.ignore_patterns, "*.jpg"));
    try testing.expect(hasPattern(cfg.ignore_patterns, "*.gif"));
    try testing.expectEqual(@as(usize, 3), cfg.ignore_patterns.items.len);
}

test "handleIgnores skips empty segments" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleIgnores(&cfg, allocator, "*.png,,*.jpg");
    try testing.expect(hasPattern(cfg.ignore_patterns, "*.png"));
    try testing.expect(hasPattern(cfg.ignore_patterns, "*.jpg"));
    try testing.expectEqual(@as(usize, 2), cfg.ignore_patterns.items.len);
}

test "handleIgnores multiple calls accumulate" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleIgnores(&cfg, allocator, "*.png,*.jpg");
    try handleIgnores(&cfg, allocator, "*.gif");
    try testing.expect(hasPattern(cfg.ignore_patterns, "*.png"));
    try testing.expect(hasPattern(cfg.ignore_patterns, "*.jpg"));
    try testing.expect(hasPattern(cfg.ignore_patterns, "*.gif"));
    try testing.expectEqual(@as(usize, 3), cfg.ignore_patterns.items.len);
}

test "handleIgnores first call clears file-loaded patterns" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    // Simulate file-loaded patterns
    try cfg.appendIgnorePattern("*.from_file");

    // First CLI call should replace file patterns
    try handleIgnores(&cfg, allocator, "*.from_cli");
    try testing.expect(!hasPattern(cfg.ignore_patterns, "*.from_file"));
    try testing.expect(hasPattern(cfg.ignore_patterns, "*.from_cli"));
    try testing.expectEqual(@as(usize, 1), cfg.ignore_patterns.items.len);
}

test "handleIgnores null value is a no-op" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleIgnores(&cfg, allocator, null);
    try testing.expectEqual(@as(usize, 0), cfg.ignore_patterns.items.len);
}
