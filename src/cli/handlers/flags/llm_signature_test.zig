const std = @import("std");
const Config = @import("../../commands/config/Config.zig");
const handleLLMSignature = @import("./llm_signature.zig").handleLLMSignature;

test "handleLLMSignature sets llm_signatures to true" {
    var cfg = Config.default(std.testing.allocator);
    defer cfg.deinit();
    try handleLLMSignature(std.testing.io, &cfg, std.testing.allocator, null);
    try std.testing.expect(cfg.llm_signatures);
}
