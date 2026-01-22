const std = @import("std");
const config = @import("./cli/config.zig").Config;

test "parse CLI args" {
    const allocator = std.heap.page_allocator;

    const args = [_][]const u8{
        "--skip-git",
        "--small",
        "1024",
    };

    const cfg = try config.parse(&args, allocator);

    try std.testing.expectEqual(true, cfg.skip_git);
    try std.testing.expectEqual(1024, cfg.small_threshold);
    try std.testing.expectEqual(false, cfg.skip_cache);
}
