const std = @import("std");
const testing = std.testing;

const Config = @import("../commands/config/config.zig").Config;
const makeTestConfig = @import("./test_config.zig").makeTestConfig;

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
