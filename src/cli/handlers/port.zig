const std = @import("std");
const Config = @import("../commands/config.zig").Config;
const makeTestConfig = @import("./test_config.zig").makeTestConfig;

/// handlePort sets the SSE/HTML dev server port (used in --watch --html mode).
pub fn handlePort(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    const v = value orelse return error.MissingValue;
    const port = std.fmt.parseInt(u16, v, 10) catch return error.InvalidPort;
    cfg.serve_port = port;
}

test "handlePort sets serve_port" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();
    try handlePort(&cfg, allocator, "8080");
    try std.testing.expectEqual(@as(u16, 8080), cfg.serve_port);
}

test "handlePort returns error for non-numeric value" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();
    try std.testing.expectError(error.InvalidPort, handlePort(&cfg, allocator, "abc"));
}
