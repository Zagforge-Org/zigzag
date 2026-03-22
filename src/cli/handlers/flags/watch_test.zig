const std = @import("std");
const testing = std.testing;
const handleWatch = @import("./watch.zig").handleWatch;
const makeTestConfig = @import("../internal/test_config.zig").makeTestConfig;

test "handleWatch enables watch mode" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try testing.expect(!cfg.watch);
    try handleWatch(&cfg, allocator, null);
    try testing.expect(cfg.watch);
}
