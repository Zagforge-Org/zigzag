const std = @import("std");
const parseTimezoneStr = @import("./timezone.zig").parseTimezoneStr;

test "parseTimezoneStr parses positive offset" {
    try std.testing.expectEqual(@as(i64, 3600), try parseTimezoneStr("+1"));
    try std.testing.expectEqual(@as(i64, 18000), try parseTimezoneStr("+5"));
    try std.testing.expectEqual(@as(i64, 19800), try parseTimezoneStr("+5:30"));
}

test "parseTimezoneStr parses negative offset" {
    try std.testing.expectEqual(@as(i64, -10800), try parseTimezoneStr("-3"));
    try std.testing.expectEqual(@as(i64, -12600), try parseTimezoneStr("-3:30"));
}

test "parseTimezoneStr parses no-sign offset" {
    try std.testing.expectEqual(@as(i64, 3600), try parseTimezoneStr("1"));
}

test "parseTimezoneStr returns error for invalid minutes" {
    try std.testing.expectError(error.InvalidTimezoneMinutes, parseTimezoneStr("+5:60"));
}

test "parseTimezoneStr returns error for invalid hours" {
    try std.testing.expectError(error.InvalidTimezoneHours, parseTimezoneStr("+15"));
}
