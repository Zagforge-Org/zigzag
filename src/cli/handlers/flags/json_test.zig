const std = @import("std");
const testing = std.testing;
const handleJson = @import("./json.zig").handleJson;
const makeTestConfig = @import("../internal/test_config.zig").makeTestConfig;

test "handleJson sets json_output to true" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();
    try std.testing.expect(!cfg.json_output);
    try handleJson(&cfg, allocator, null);
    try std.testing.expect(cfg.json_output);
}
