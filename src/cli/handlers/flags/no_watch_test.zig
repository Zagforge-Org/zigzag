const std = @import("std");
const handleNoWatch = @import("./no_watch.zig").handleNoWatch;
const makeTestConfig = @import("../internal/test_config.zig").makeTestConfig;

test "handleNoWatch disables watch mode" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    cfg.watch = true;
    try std.testing.expect(cfg.watch);
    try handleNoWatch(&cfg, allocator, null);
    try std.testing.expect(!cfg.watch);
    try std.testing.expect(cfg._no_watch_set_by_cli);
}
