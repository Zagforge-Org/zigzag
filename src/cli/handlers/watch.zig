const std = @import("std");
const testing = std.testing;

const Config = @import("../commands/config.zig").Config;
const makeTestConfig = @import("./test_config.zig").makeTestConfig;

/// handleWatch enables watch mode.
pub fn handleWatch(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    cfg.watch = true;
}

test "handleWatch enables watch mode" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try testing.expect(!cfg.watch);
    try handleWatch(&cfg, allocator, null);
    try testing.expect(cfg.watch);
}

