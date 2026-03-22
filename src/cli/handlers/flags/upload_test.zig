const std = @import("std");
const handleUpload = @import("./upload.zig").handleUpload;
const makeTestConfig = @import("../internal/test_config.zig").makeTestConfig;

test "handleUpload sets cfg.upload to true" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try std.testing.expect(!cfg.upload);
    try handleUpload(&cfg, allocator, null);
    try std.testing.expect(cfg.upload);
}

test "handleUpload ignores value argument" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleUpload(&cfg, allocator, "unexpected");
    try std.testing.expect(cfg.upload);
}
