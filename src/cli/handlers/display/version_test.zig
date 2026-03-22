const std = @import("std");
const printVersion = @import("./version.zig").printVersion;
const VERSION = @import("./version.zig").VERSION;
const makeTestConfig = @import("../internal/test_config.zig").makeTestConfig;

test "printVersion should print version information" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();
    try std.testing.expectEqualStrings(VERSION, cfg.version);
}
