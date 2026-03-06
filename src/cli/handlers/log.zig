const std = @import("std");
const testing = std.testing;
const Config = @import("../commands/config/config.zig").Config;
const makeTestConfig = @import("./test_config.zig").makeTestConfig;

pub fn handleLog(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    cfg.log = true;
}

test "handleLog enables log mode" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try testing.expect(!cfg.log);
    try handleLog(&cfg, allocator, null);
    try testing.expect(cfg.log);
}
