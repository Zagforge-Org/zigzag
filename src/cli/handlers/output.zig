const std = @import("std");
const testing = std.testing;

const Config = @import("../commands/config/config.zig").Config;
const makeTestConfig = @import("./test_config.zig").makeTestConfig;

/// handleOutput sets the output filename for the generated report.
pub fn handleOutput(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    if (value) |filename| {
        const trimmed = std.mem.trim(u8, filename, " \t\n\r");
        if (trimmed.len == 0) return;

        if (cfg.output) |existing| allocator.free(existing);
        cfg.output = try allocator.dupe(u8, trimmed);
    }
}

test "handleOutput sets output filename" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleOutput(&cfg, allocator, "custom.md");
    try testing.expectEqualStrings("custom.md", cfg.output.?);
}

test "handleOutput trims whitespace" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleOutput(&cfg, allocator, "  output.md  ");
    try testing.expectEqualStrings("output.md", cfg.output.?);
}

test "handleOutput ignores empty filename" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleOutput(&cfg, allocator, "   ");
    try testing.expect(cfg.output == null);
}

test "handleOutput replaces previous output value" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleOutput(&cfg, allocator, "first.md");
    try handleOutput(&cfg, allocator, "second.md");
    try testing.expectEqualStrings("second.md", cfg.output.?);
}
