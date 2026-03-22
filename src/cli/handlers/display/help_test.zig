const std = @import("std");
const printHelp = @import("./help.zig").printHelp;
const makeTestConfig = @import("../internal/test_config.zig").makeTestConfig;

test "printHelp runs without error" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();
    try printHelp(&cfg, allocator, null);
}
