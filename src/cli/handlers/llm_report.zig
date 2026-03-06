const std = @import("std");
const testing = std.testing;

const Config = @import("../commands/config/config.zig").Config;
const makeTestConfig = @import("./test_config.zig").makeTestConfig;

/// handleLlmReport enables LLM-optimized report output alongside the markdown report.
pub fn handleLlmReport(cfg: *Config, allocator: std.mem.Allocator, _: ?[]const u8) anyerror!void {
    _ = allocator;
    cfg.llm_report = true;
}

test "handleLlmReport sets llm_report to true" {
    var cfg = Config.default(std.testing.allocator);
    defer cfg.deinit();
    try handleLlmReport(&cfg, std.testing.allocator, null);
    try std.testing.expect(cfg.llm_report);
}
