const std = @import("std");
const writeVersion = @import("./version.zig").writeVersion;
const VERSION = @import("./version.zig").VERSION;
const makeTestConfig = @import("../internal/test_config.zig").makeTestConfig;

test "printVersion should print version information" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();
    try std.testing.expectEqualStrings(VERSION, cfg.version);
}

test "writeVersion writes the configured version" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    try writeVersion(&aw.writer, &cfg);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), cfg.version) != null);
}
