const std = @import("std");
const Config = @import("../commands/config/config.zig").Config;
const makeTestConfig = @import("./test_config.zig").makeTestConfig;

/// handleOpen sets the open_browser flag so serve/watch opens the browser on start.
pub fn handleOpen(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    cfg.open_browser = true;
}

test "handleOpen sets open_browser" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();
    try std.testing.expect(!cfg.open_browser);
    try handleOpen(&cfg, allocator, null);
    try std.testing.expect(cfg.open_browser);
}
