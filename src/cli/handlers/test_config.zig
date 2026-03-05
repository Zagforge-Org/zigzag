const std = @import("std");
const Config = @import("../commands/config.zig").Config;

pub fn makeTestConfig(allocator: std.mem.Allocator) Config {
    return Config.initDefault(allocator);
}
