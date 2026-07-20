const std = @import("std");

/// A binary file detected during the scan.
pub const BinaryEntry = struct {
    path: []const u8,
    size: u64,
    mtime: i128,
    extension: []const u8,
};

/// A source/text file that was read and will be rendered into reports.
pub const JobEntry = struct {
    path: []const u8,
    content: []u8,
    size: u64,
    mtime: i128,
    extension: []const u8,
    line_count: usize,

    const Self = @This();

    /// Language id for markdown code blocks.
    pub fn getLanguage(self: *const Self) []const u8 {
        if (self.extension.len == 0) return "";
        if (self.extension[0] == '.') return self.extension[1..];
        return self.extension;
    }

    /// Format file size in human-readable units (B/KB/MB/GB).
    pub fn formatSize(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        const units = [_][]const u8{ "B", "KB", "MB", "GB" };

        var size = @as(f64, @floatFromInt(self.size));
        var unit_index: usize = 0;

        while (size >= 1024.0 and unit_index < units.len - 1) {
            size /= 1024.0;
            unit_index += 1;
        }

        if (unit_index == 0) {
            return std.fmt.allocPrint(allocator, "{d} {s}", .{
                self.size,
                units[unit_index],
            });
        }

        return std.fmt.allocPrint(allocator, "{d:.2} {s}", .{
            size,
            units[unit_index],
        });
    }

    /// Format modification time as `YYYY-MM-DD HH:MM:SS (UTC+offset)`.
    /// `timezone_offset` is in seconds from UTC (e.g. 3600 for UTC+1).
    pub fn formatMtime(self: *const Self, allocator: std.mem.Allocator, timezone_offset: ?i64) ![]u8 {
        // mtime is nanoseconds since epoch (i128).
        const timestamp_seconds: i64 = @intCast(@divFloor(self.mtime, std.time.ns_per_s));

        // Apply the offset to convert UTC to local time.
        const local_timestamp = if (timezone_offset) |offset|
            timestamp_seconds + offset
        else
            timestamp_seconds;

        const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(local_timestamp) };
        const day_seconds = epoch_seconds.getDaySeconds();
        const epoch_day = epoch_seconds.getEpochDay();
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        const tz_suffix = if (timezone_offset) |offset| blk: {
            const abs_offset: i64 = if (offset < 0) -offset else offset;
            const hours = @divFloor(abs_offset, 3600);
            const mins = @mod(@divFloor(abs_offset, 60), 60);
            const sign: u8 = if (offset >= 0) '+' else '-';

            if (mins == 0) {
                break :blk try std.fmt.allocPrint(allocator, " (UTC{c}{d})", .{ sign, hours });
            } else {
                break :blk try std.fmt.allocPrint(allocator, " (UTC{c}{d}:{d:0>2})", .{ sign, hours, mins });
            }
        } else " (UTC)";
        defer if (timezone_offset != null) allocator.free(tz_suffix);

        return std.fmt.allocPrint(
            allocator,
            "{d}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}{s}",
            .{
                year_day.year,
                month_day.month.numeric(),
                month_day.day_index + 1,
                day_seconds.getHoursIntoDay(),
                day_seconds.getMinutesIntoHour(),
                day_seconds.getSecondsIntoMinute(),
                tz_suffix,
            },
        );
    }
};
