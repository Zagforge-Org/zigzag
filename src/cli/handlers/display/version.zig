const std = @import("std");
const Config = @import("../../commands/config/config.zig").Config;
const stdoutPrint = @import("../../../fs/stdout.zig").stdoutPrint;
pub const VERSION = @import("../../commands/config/config.zig").VERSION;

/// printVersion prints version information.
pub fn printVersion(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    try stdoutPrint(
        \\version {s}
        \\
    , .{
        cfg.version,
    });
}
