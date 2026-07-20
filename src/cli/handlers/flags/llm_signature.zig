const std = @import("std");
const Config = @import("../../commands/config/Config.zig");

/// handleLLMSignature sets the llm_signature flag
pub fn handleLLMSignature(_: std.Io, cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    cfg.llm_signatures = true;
}
