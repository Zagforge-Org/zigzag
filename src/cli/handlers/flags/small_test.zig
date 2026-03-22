const std = @import("std");
const testing = std.testing;
const handleSmall = @import("./small.zig").handleSmall;
const makeTestConfig = @import("../internal/test_config.zig").makeTestConfig;

test "handleSmall handles small option" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();
    try handleSmall(&cfg, allocator, "1024");
    try testing.expectEqual(1024, cfg.small_threshold);
}
