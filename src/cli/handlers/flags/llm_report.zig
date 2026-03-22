const std = @import("std");
const Config = @import("../../commands/config/config.zig").Config;

/// handleLlmReport enables LLM-optimized report output alongside the markdown report.
pub fn handleLlmReport(cfg: *Config, allocator: std.mem.Allocator, _: ?[]const u8) anyerror!void {
    _ = allocator;
    cfg.llm_report = true;
}
