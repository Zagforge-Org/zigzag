const std = @import("std");

/// Parses a timezone string into an offset in seconds from UTC.
pub fn parseTimezoneStr(tz_str: []const u8) !i64 {
    if (tz_str.len == 0) return 0;
    const is_negative = tz_str[0] == '-';
    const start_idx: usize = if (tz_str[0] == '+' or tz_str[0] == '-') 1 else 0;

    var hours: i64 = 0;
    var minutes: i64 = 0;

    if (std.mem.indexOf(u8, tz_str, ":")) |colon_pos| {
        hours = try std.fmt.parseInt(i64, tz_str[start_idx..colon_pos], 10);
        minutes = try std.fmt.parseInt(i64, tz_str[colon_pos + 1 ..], 10);
        if (minutes < 0 or minutes > 59) return error.InvalidTimezoneMinutes;
        if (hours < 0 or hours > 14) return error.InvalidTimezoneHours;
    } else {
        hours = try std.fmt.parseInt(i64, tz_str[start_idx..], 10);
        if (hours < 0 or hours > 14) return error.InvalidTimezoneHours;
    }

    var offset_seconds = hours * 3600 + minutes * 60;
    if (is_negative) offset_seconds = -offset_seconds;
    return offset_seconds;
}
