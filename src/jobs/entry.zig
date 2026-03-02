const std = @import("std");

pub const BinaryEntry = struct {
    path: []const u8,
    size: u64,
    mtime: i128,
    extension: []const u8,
};

pub const JobEntry = struct {
    path: []const u8,
    content: []u8,
    size: u64,
    mtime: i128,
    extension: []const u8,
    line_count: usize,

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

test "BinaryEntry has expected fields" {
    const entry = BinaryEntry{
        .path = "assets/logo.png",
        .size = 4096,
        .mtime = 1700000000000000000,
        .extension = ".png",
    };
    try std.testing.expectEqualStrings("assets/logo.png", entry.path);
    try std.testing.expectEqual(@as(u64, 4096), entry.size);
    try std.testing.expectEqual(@as(i128, 1700000000000000000), entry.mtime);
    try std.testing.expectEqualStrings(".png", entry.extension);
}

test "JobEntry.getLanguage strips leading dot" {
    const entry = JobEntry{ .path = "a.zig", .content = @constCast(""), .size = 0, .mtime = 0, .extension = ".zig", .line_count = 0 };
    try std.testing.expectEqualStrings("zig", entry.getLanguage());
}

test "JobEntry.getLanguage returns empty string for empty extension" {
    const entry = JobEntry{ .path = "Makefile", .content = @constCast(""), .size = 0, .mtime = 0, .extension = "", .line_count = 0 };
    try std.testing.expectEqualStrings("", entry.getLanguage());
}

test "JobEntry.getLanguage returns extension unchanged when no leading dot" {
    const entry = JobEntry{ .path = "foo", .content = @constCast(""), .size = 0, .mtime = 0, .extension = "zig", .line_count = 0 };
    try std.testing.expectEqualStrings("zig", entry.getLanguage());
}

test "JobEntry.line_count field stores value" {
    const entry = JobEntry{ .path = "x.zig", .content = @constCast(""), .size = 0, .mtime = 0, .extension = ".zig", .line_count = 42 };
    try std.testing.expectEqual(@as(usize, 42), entry.line_count);
}

test "JobEntry.formatSize formats bytes" {
    const alloc = std.testing.allocator;
    var entry = JobEntry{ .path = "", .content = @constCast(""), .size = 512, .mtime = 0, .extension = "", .line_count = 0 };
    const s = try entry.formatSize(alloc);
    defer alloc.free(s);
    try std.testing.expect(std.mem.indexOf(u8, s, "512 B") != null);
}

test "JobEntry.formatSize formats kilobytes" {
    const alloc = std.testing.allocator;
    var entry = JobEntry{ .path = "", .content = @constCast(""), .size = 2048, .mtime = 0, .extension = "", .line_count = 0 };
    const s = try entry.formatSize(alloc);
    defer alloc.free(s);
    try std.testing.expect(std.mem.indexOf(u8, s, "KB") != null);
}

test "JobEntry.formatSize formats megabytes" {
    const alloc = std.testing.allocator;
    var entry = JobEntry{ .path = "", .content = @constCast(""), .size = 2 * 1024 * 1024, .mtime = 0, .extension = "", .line_count = 0 };
    const s = try entry.formatSize(alloc);
    defer alloc.free(s);
    try std.testing.expect(std.mem.indexOf(u8, s, "MB") != null);
}

test "JobEntry.formatMtime formats UTC timestamp" {
    const alloc = std.testing.allocator;
    // 2023-11-14 22:13:20 UTC = 1700000000 seconds since epoch
    var entry = JobEntry{ .path = "", .content = @constCast(""), .size = 0, .mtime = 1700000000 * std.time.ns_per_s, .extension = "", .line_count = 0 };
    const s = try entry.formatMtime(alloc, null);
    defer alloc.free(s);
    try std.testing.expect(std.mem.indexOf(u8, s, "2023") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "(UTC)") != null);
}
