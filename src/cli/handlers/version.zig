const std = @import("std");
const testing = std.testing;

const Config = @import("../commands/config/config.zig").Config;
const stdoutPrint = @import("../../fs/stdout.zig").stdoutPrint;
const makeTestConfig = @import("./test_config.zig").makeTestConfig;
const VERSION = @import("../commands/config/config.zig").VERSION;

/// printVersion prints version information.
pub fn printVersion(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    try stdoutPrint(
        \\version {s}
        \\
    , .{
        cfg.version,
    });
}

test "printVersion should print version information" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();
    try testing.expectEqualStrings(VERSION, cfg.version);
}
