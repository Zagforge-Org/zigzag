const std = @import("std");
const handleHtml = @import("./html.zig").handleHtml;
const makeTestConfig = @import("../internal/test_config.zig").makeTestConfig;

test "handleHtml sets html_output to true" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();
    try std.testing.expect(!cfg.html_output);
    try handleHtml(&cfg, allocator, null);
    try std.testing.expect(cfg.html_output);
}
