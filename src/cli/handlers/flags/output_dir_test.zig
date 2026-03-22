const std = @import("std");
const testing = std.testing;
const handleOutputDir = @import("./output_dir.zig").handleOutputDir;
const makeTestConfig = @import("../internal/test_config.zig").makeTestConfig;

test "handleOutputDir sets output_dir" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleOutputDir(&cfg, allocator, "my-reports");
    try testing.expectEqualStrings("my-reports", cfg.output_dir.?);
    try testing.expect(cfg._output_dir_set_by_cli);
}

test "handleOutputDir trims whitespace" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleOutputDir(&cfg, allocator, "  reports/  ");
    try testing.expectEqualStrings("reports/", cfg.output_dir.?);
}

test "handleOutputDir replaces previous value" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleOutputDir(&cfg, allocator, "first");
    try handleOutputDir(&cfg, allocator, "second");
    try testing.expectEqualStrings("second", cfg.output_dir.?);
}

test "handleOutputDir ignores empty value" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleOutputDir(&cfg, allocator, "   ");
    try testing.expect(cfg.output_dir == null);
    try testing.expect(!cfg._output_dir_set_by_cli);
}
