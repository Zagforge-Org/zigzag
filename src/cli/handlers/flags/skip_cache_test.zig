const std = @import("std");
const testing = std.testing;
const handleSkipCache = @import("./skip_cache.zig").handleSkipCache;
const makeTestConfig = @import("../internal/test_config.zig").makeTestConfig;

test "handleSkipCache handles skip-cache option" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();
    try handleSkipCache(&cfg, allocator, null);
    try testing.expectEqual(true, cfg.skip_cache);
}
