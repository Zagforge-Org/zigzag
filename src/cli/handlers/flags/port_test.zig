const std = @import("std");
const handlePort = @import("./port.zig").handlePort;
const makeTestConfig = @import("../internal/test_config.zig").makeTestConfig;

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
