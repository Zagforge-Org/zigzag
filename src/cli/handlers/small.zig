const std = @import("std");
const testing = std.testing;

const Config = @import("../commands/config.zig").Config;
const makeTestConfig = @import("./test_config.zig").makeTestConfig;

/// handleSmall handles the small option.
pub fn handleSmall(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    if (value) |v| {
        cfg.small_threshold = try std.fmt.parseInt(usize, v, 10);
    }
}

test "handleSmall handles small option" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();
    try handleSmall(&cfg, allocator, "1024");
    try testing.expectEqual(1024, cfg.small_threshold);
}
