const std = @import("std");
const handleOpen = @import("./open.zig").handleOpen;
const makeTestConfig = @import("../internal/test_config.zig").makeTestConfig;

test "handleOpen sets open_browser" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();
    try std.testing.expect(!cfg.open_browser);
    try handleOpen(&cfg, allocator, null);
    try std.testing.expect(cfg.open_browser);
}
