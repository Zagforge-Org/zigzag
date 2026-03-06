const std = @import("std");
const testing = std.testing;

const Config = @import("../commands/config/config.zig").Config;
const makeTestConfig = @import("./test_config.zig").makeTestConfig;

/// handleHtml enables HTML report output alongside the markdown report.
pub fn handleHtml(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    cfg.html_output = true;
}

test "handleHtml sets html_output to true" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();
    try std.testing.expect(!cfg.html_output);
    try handleHtml(&cfg, allocator, null);
    try std.testing.expect(cfg.html_output);
}
