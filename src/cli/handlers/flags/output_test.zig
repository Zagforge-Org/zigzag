const std = @import("std");
const testing = std.testing;
const handleOutput = @import("./output.zig").handleOutput;
const makeTestConfig = @import("../internal/test_config.zig").makeTestConfig;

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
