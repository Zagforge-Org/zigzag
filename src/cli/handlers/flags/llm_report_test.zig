const std = @import("std");
const handleLlmReport = @import("./llm_report.zig").handleLlmReport;
const Config = @import("../../commands/config/config.zig").Config;

test "handleLlmReport sets llm_report to true" {
    var cfg = Config.default(std.testing.allocator);
    defer cfg.deinit();
    try handleLlmReport(&cfg, std.testing.allocator, null);
    try std.testing.expect(cfg.llm_report);
}
