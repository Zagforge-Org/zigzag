// src/cli/handlers/internal/test_config.zig
const std = @import("std");
const Config = @import("../../commands/config/config.zig").Config;

pub fn makeTestConfig(allocator: std.mem.Allocator) Config {
    return Config.default(allocator);
}
