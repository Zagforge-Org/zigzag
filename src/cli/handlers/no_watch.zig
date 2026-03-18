const std = @import("std");
const testing = std.testing;

const Config = @import("../commands/config/config.zig").Config;
const makeTestConfig = @import("./test_config.zig").makeTestConfig;

/// handleNoWatch disables watch mode, overriding any file config setting.
pub fn handleNoWatch(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    cfg.watch = false;
    cfg._no_watch_set_by_cli = true;
}

test "handleNoWatch disables watch mode" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    cfg.watch = true;
    try testing.expect(cfg.watch);
    try handleNoWatch(&cfg, allocator, null);
    try testing.expect(!cfg.watch);
    try testing.expect(cfg._no_watch_set_by_cli);
}
