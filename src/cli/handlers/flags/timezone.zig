const std = @import("std");
const Config = @import("../../commands/config/Config.zig");
const parseTimezoneStr = @import("../../commands/config/timezone.zig").parseTimezoneStr;

/// handleTimezone handles the timezone option.
/// Accepts formats like: "+1", "-5", "+5:30", "-3:30"
pub fn handleTimezone(_: std.Io, cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    const tz_str = value orelse return;
    if (tz_str.len == 0) return;
    cfg.timezone_offset = try parseTimezoneStr(tz_str);
}
