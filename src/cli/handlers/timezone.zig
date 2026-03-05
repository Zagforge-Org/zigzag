const std = @import("std");
const testing = std.testing;

const Config = @import("../commands/config.zig").Config;
const makeTestConfig = @import("./test_config.zig").makeTestConfig;

/// handleTimezone handles the timezone option.
/// Accepts formats like: "+1", "-5", "+5:30", "-3:30"
pub fn handleTimezone(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    const tz_str = value orelse return;
    if (tz_str.len == 0) return;
    cfg.timezone_offset = try Config.parseTimezoneStr(tz_str);
}

test "handleTimezone handles timezone option" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleTimezone(&cfg, allocator, "+5");
    try testing.expectEqual(@as(i64, 18000), cfg.timezone_offset);

    try handleTimezone(&cfg, allocator, "-3:30");
    try testing.expectEqual(@as(i64, -12600), cfg.timezone_offset);
}

test "handleTimezone handles invalid timezone option" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    const result_invalid_mins = handleTimezone(&cfg, allocator, "+5:60");
    try testing.expectError(error.InvalidTimezoneMinutes, result_invalid_mins);

    const result_invalid_format = handleTimezone(&cfg, allocator, "-3:30:00");
    try testing.expectError(error.InvalidCharacter, result_invalid_format);
}
