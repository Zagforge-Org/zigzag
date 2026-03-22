const std = @import("std");
const testing = std.testing;
const handleLog = @import("./log.zig").handleLog;
const makeTestConfig = @import("../internal/test_config.zig").makeTestConfig;

test "handleLog enables log mode" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try testing.expect(!cfg.log);
    try handleLog(&cfg, allocator, null);
    try testing.expect(cfg.log);
}
