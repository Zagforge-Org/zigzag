const std = @import("std");
const testing = std.testing;

const Config = @import("../commands/config.zig").Config;
const makeTestConfig = @import("./test_config.zig").makeTestConfig;

/// handleIgnore handles the ignore option - can be called multiple times.
/// When called via CLI, the first invocation replaces any file-config patterns.
/// Subsequent CLI invocations accumulate additional patterns.
pub fn handleIgnore(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    if (value) |pattern| {
        const trimmed = std.mem.trim(u8, pattern, " \t\n\r");
        if (trimmed.len == 0) return;

        // First CLI --ignore call: replace file-loaded patterns (CLI overrides file config)
        if (!cfg._patterns_set_by_cli) {
            cfg._patterns_set_by_cli = true;
            cfg.clearIgnorePatterns(allocator);
        }

        try cfg.appendIgnorePattern(allocator, trimmed);
    }
}

test "handleIgnore handles single pattern" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleIgnore(&cfg, allocator, "*.png");
    try testing.expect(std.mem.indexOf(u8, cfg.ignore_patterns, "*.png") != null);
}

test "handleIgnore accumulates multiple patterns" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleIgnore(&cfg, allocator, "*.png");
    try handleIgnore(&cfg, allocator, "*.jpg");
    try testing.expect(std.mem.indexOf(u8, cfg.ignore_patterns, "*.png") != null);
    try testing.expect(std.mem.indexOf(u8, cfg.ignore_patterns, "*.jpg") != null);
}

test "handleIgnore trims whitespace from pattern" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleIgnore(&cfg, allocator, "  *.png  ");
    try testing.expect(std.mem.indexOf(u8, cfg.ignore_patterns, "*.png") != null);
    try testing.expect(std.mem.indexOf(u8, cfg.ignore_patterns, " ") == null);
}

test "handleIgnore ignores empty pattern" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleIgnore(&cfg, allocator, "   ");
    try testing.expectEqualStrings("", cfg.ignore_patterns);
}

test "handleIgnore CLI overrides file-loaded patterns" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    // Simulate file-loaded patterns
    try cfg.appendIgnorePattern(allocator, "*.from_file");

    // First CLI call should replace file patterns
    try handleIgnore(&cfg, allocator, "*.from_cli");
    try testing.expect(std.mem.indexOf(u8, cfg.ignore_patterns, "*.from_file") == null);
    try testing.expect(std.mem.indexOf(u8, cfg.ignore_patterns, "*.from_cli") != null);

    // Second CLI call accumulates
    try handleIgnore(&cfg, allocator, "*.also_cli");
    try testing.expect(std.mem.indexOf(u8, cfg.ignore_patterns, "*.from_cli") != null);
    try testing.expect(std.mem.indexOf(u8, cfg.ignore_patterns, "*.also_cli") != null);
}
