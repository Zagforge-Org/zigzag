const std = @import("std");
const testing = std.testing;
const handleMmap = @import("./mmap.zig").handleMmap;
const makeTestConfig = @import("../internal/test_config.zig").makeTestConfig;

test "handleMmap handles mmap option" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();
    try handleMmap(&cfg, allocator, "2048");
    try testing.expectEqual(2048, cfg.mmap_threshold);
}
