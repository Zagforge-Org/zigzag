const std = @import("std");
const Config = @import("../../commands/config/config.zig").Config;

/// handleNoWatch disables watch mode, overriding any file config setting.
pub fn handleNoWatch(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    cfg.watch = false;
    cfg._no_watch_set_by_cli = true;
}
