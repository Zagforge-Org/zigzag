const std = @import("std");
const testing = std.testing;
const handleTimezone = @import("./timezone.zig").handleTimezone;
const makeTestConfig = @import("../internal/test_config.zig").makeTestConfig;

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
