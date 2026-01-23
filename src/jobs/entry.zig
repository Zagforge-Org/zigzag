const std = @import("std");

pub const JobEntry = struct {
    path: []const u8,
    content: []u8,
    size: u64,
    mtime: i128,
    extension: []const u8,

    const Self = @This();

    /// Get the language identifier for markdown code blocks
    pub fn getLanguage(self: *const Self) []const u8 {
        if (self.extension.len == 0) return "";

        // Remove the leading dot if present
        if (self.extension[0] == '.') {
            return self.extension[1..];
        }
        return self.extension;
    }

    /// Format file size in human-readable format
    pub fn formatSize(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        const size = self.size;

        if (size < 1024) {
            return std.fmt.allocPrint(allocator, "{d} B", .{size});
        } else if (size < 1024 * 1024) {
            const kb = @as(f64, @floatFromInt(size)) / 1024.0;
            return std.fmt.allocPrint(allocator, "{d:.2} KB", .{kb});
        } else if (size < 1024 * 1024 * 1024) {
            const mb = @as(f64, @floatFromInt(size)) / (1024.0 * 1024.0);
            return std.fmt.allocPrint(allocator, "{d:.2} MB", .{mb});
        } else {
            const gb = @as(f64, @floatFromInt(size)) / (1024.0 * 1024.0 * 1024.0);
            return std.fmt.allocPrint(allocator, "{d:.2} GB", .{gb});
        }
    }

    /// Format modification time in human-readable format
    /// If timezone_offset is provided, converts from UTC to local time
    /// timezone_offset is in seconds (e.g., 3600 for UTC+1)
    pub fn formatMtime(self: *const Self, allocator: std.mem.Allocator, timezone_offset: ?i64) ![]u8 {
        // mtime is in nanoseconds since epoch (i128)
        const timestamp_seconds: i64 = @intCast(@divFloor(self.mtime, std.time.ns_per_s));

        // DEBUG: Log what we're working with
        std.log.debug("formatMtime DEBUG:", .{});
        std.log.debug("  mtime (ns): {d}", .{self.mtime});
        std.log.debug("  timestamp_seconds: {d}", .{timestamp_seconds});
        std.log.debug("  timezone_offset: {?d}", .{timezone_offset});

        // Apply timezone offset to convert UTC to local time
        const local_timestamp = if (timezone_offset) |offset| blk: {
            const adjusted = timestamp_seconds + offset;
            std.log.debug("  adjusted timestamp: {d}", .{adjusted});
            break :blk adjusted;
        } else timestamp_seconds;

        const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(local_timestamp) };
        const day_seconds = epoch_seconds.getDaySeconds();
        const epoch_day = epoch_seconds.getEpochDay();
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        // Format timezone suffix
        const tz_suffix = if (timezone_offset) |offset| blk: {
            const abs_offset: i64 = if (offset < 0) -offset else offset;
            const hours = @divFloor(abs_offset, 3600);
            const mins = @mod(@divFloor(abs_offset, 60), 60);

            if (offset >= 0) {
                if (mins == 0) {
                    break :blk try std.fmt.allocPrint(allocator, " (UTC+{d})", .{hours});
                } else {
                    break :blk try std.fmt.allocPrint(allocator, " (UTC+{d}:{d:0>2})", .{ hours, mins });
                }
            } else {
                if (mins == 0) {
                    break :blk try std.fmt.allocPrint(allocator, " (UTC-{d})", .{hours});
                } else {
                    break :blk try std.fmt.allocPrint(allocator, " (UTC-{d}:{d:0>2})", .{ hours, mins });
                }
            }
        } else " (UTC)";
        defer if (timezone_offset != null) allocator.free(tz_suffix);

        const result = try std.fmt.allocPrint(
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

        std.log.debug("  formatted result: {s}", .{result});
        return result;
    }
};
