const std = @import("std");
const testing = std.testing;

const Config = @import("../commands/config.zig").Config;
const makeTestConfig = @import("./test_config.zig").makeTestConfig;

/// handleOutputDir sets the base output directory for generated reports.
pub fn handleOutputDir(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    if (value) |v| {
        const trimmed = std.mem.trim(u8, v, " \t\r\n");
        if (trimmed.len == 0) return;
        if (cfg._output_dir_allocated) {
            if (cfg.output_dir) |existing| allocator.free(existing);
        }
        cfg.output_dir = try allocator.dupe(u8, trimmed);
        cfg._output_dir_allocated = true;
        cfg._output_dir_set_by_cli = true;
    }
}

test "handleOutputDir sets output_dir" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleOutputDir(&cfg, allocator, "my-reports");
    try testing.expectEqualStrings("my-reports", cfg.output_dir.?);
    try testing.expect(cfg._output_dir_set_by_cli);
}

test "handleOutputDir trims whitespace" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleOutputDir(&cfg, allocator, "  reports/  ");
    try testing.expectEqualStrings("reports/", cfg.output_dir.?);
}

test "handleOutputDir replaces previous value" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleOutputDir(&cfg, allocator, "first");
    try handleOutputDir(&cfg, allocator, "second");
    try testing.expectEqualStrings("second", cfg.output_dir.?);
}

test "handleOutputDir ignores empty value" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleOutputDir(&cfg, allocator, "   ");
    try testing.expect(cfg.output_dir == null);
    try testing.expect(!cfg._output_dir_set_by_cli);
}
