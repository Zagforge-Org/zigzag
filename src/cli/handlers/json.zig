const std = @import("std");
const testing = std.testing;

const Config = @import("../commands/config/config.zig").Config;
const makeTestConfig = @import("./test_config.zig").makeTestConfig;

/// handleJson enables JSON report output alongside the markdown report.
pub fn handleJson(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    cfg.json_output = true;
}

test "handleJson sets json_output to true" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();
    try std.testing.expect(!cfg.json_output);
    try handleJson(&cfg, allocator, null);
    try std.testing.expect(cfg.json_output);
}

