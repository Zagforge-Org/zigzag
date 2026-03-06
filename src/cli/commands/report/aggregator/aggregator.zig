const std = @import("std");
const JobEntry = @import("../../../../jobs/entry.zig").JobEntry;
const BinaryEntry = @import("../../../../jobs/entry.zig").BinaryEntry;

/// Per-language aggregate statistics.
pub const LanguageStat = struct {
    name: []const u8,
    files: usize,
    lines: usize,
    size_bytes: u64,
};

/// Pre-computed report data: sorted entries, language stats, totals, and timestamp.
/// Build once with `init`, pass by pointer to every writer, free with `deinit`.
pub const ReportData = struct {
    allocator: std.mem.Allocator,
    sorted_files: std.ArrayList(JobEntry),
    sorted_binaries: std.ArrayList(BinaryEntry),
    lang_list: std.ArrayList(LanguageStat),
    total_lines: usize,
    total_size: u64,
    /// "YYYY-MM-DD HH:MM:SS" (timezone-adjusted)
    generated_at_str: []u8,
    /// "YYYY-MM-DD" (timezone-adjusted)
    date_str: []u8,

    pub fn init(
        allocator: std.mem.Allocator,
        file_entries: *const std.StringHashMap(JobEntry),
        binary_entries: *const std.StringHashMap(BinaryEntry),
        timezone_offset: ?i64,
    ) !ReportData {
        // --- Timestamp ---
        const now = std.time.timestamp();
        const local_now = if (timezone_offset) |offset| now + offset else now;
        const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(local_now) };
        const day_seconds = epoch_seconds.getDaySeconds();
        const epoch_day = epoch_seconds.getEpochDay();
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        const generated_at_str = try std.fmt.allocPrint(
            allocator,
            "{d}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}",
            .{
                year_day.year,
                month_day.month.numeric(),
                month_day.day_index + 1,
                day_seconds.getHoursIntoDay(),
                day_seconds.getMinutesIntoHour(),
                day_seconds.getSecondsIntoMinute(),
            },
        );
        errdefer allocator.free(generated_at_str);

        const date_str = try std.fmt.allocPrint(
            allocator,
            "{d}-{d:0>2}-{d:0>2}",
            .{
                year_day.year,
                month_day.month.numeric(),
                month_day.day_index + 1,
            },
        );
        errdefer allocator.free(date_str);

        // --- Language aggregation ---
        var lang_map = std.StringHashMap(LanguageStat).init(allocator);
        defer {
            var it = lang_map.iterator();
            while (it.next()) |entry| allocator.free(entry.value_ptr.name);
            lang_map.deinit();
        }

        var total_lines: usize = 0;
        var total_size: u64 = 0;

        var fit = file_entries.iterator();
        while (fit.next()) |entry| {
            const e = entry.value_ptr;
            total_lines += e.line_count;
            total_size += e.size;

            const lang = e.getLanguage();
            const lang_name = if (lang.len > 0) lang else "unknown";
            const gop = try lang_map.getOrPut(lang_name);
            if (!gop.found_existing) {
                gop.value_ptr.* = .{
                    .name = try allocator.dupe(u8, lang_name),
                    .files = 0,
                    .lines = 0,
                    .size_bytes = 0,
                };
            }
            gop.value_ptr.files += 1;
            gop.value_ptr.lines += e.line_count;
            gop.value_ptr.size_bytes += e.size;
        }

        // --- Sort language stats by name ---
        // Transfer name ownership from lang_map to lang_list before map cleanup.
        var lang_list: std.ArrayList(LanguageStat) = .empty;
        errdefer {
            for (lang_list.items) |ls| allocator.free(ls.name);
            lang_list.deinit(allocator);
        }
        var lit = lang_map.iterator();
        while (lit.next()) |entry| {
            try lang_list.append(allocator, entry.value_ptr.*);
            // Blank name so the map's defer-free is a no-op for this entry.
            entry.value_ptr.name = "";
        }
        std.mem.sort(LanguageStat, lang_list.items, {}, struct {
            fn lessThan(_: void, a: LanguageStat, b: LanguageStat) bool {
                return std.mem.lessThan(u8, a.name, b.name);
            }
        }.lessThan);

        // --- Sort file entries by path ---
        var sorted_files: std.ArrayList(JobEntry) = .empty;
        errdefer sorted_files.deinit(allocator);
        fit = file_entries.iterator();
        while (fit.next()) |entry| try sorted_files.append(allocator, entry.value_ptr.*);
        std.mem.sort(JobEntry, sorted_files.items, {}, struct {
            fn lessThan(_: void, a: JobEntry, b: JobEntry) bool {
                return std.mem.lessThan(u8, a.path, b.path);
            }
        }.lessThan);

        // --- Sort binary entries by path ---
        var sorted_binaries: std.ArrayList(BinaryEntry) = .empty;
        errdefer sorted_binaries.deinit(allocator);
        var bit = binary_entries.iterator();
        while (bit.next()) |entry| try sorted_binaries.append(allocator, entry.value_ptr.*);
        std.mem.sort(BinaryEntry, sorted_binaries.items, {}, struct {
            fn lessThan(_: void, a: BinaryEntry, b: BinaryEntry) bool {
                return std.mem.lessThan(u8, a.path, b.path);
            }
        }.lessThan);

        return .{
            .allocator = allocator,
            .sorted_files = sorted_files,
            .sorted_binaries = sorted_binaries,
            .lang_list = lang_list,
            .total_lines = total_lines,
            .total_size = total_size,
            .generated_at_str = generated_at_str,
            .date_str = date_str,
        };
    }

    pub fn deinit(self: *ReportData) void {
        for (self.lang_list.items) |ls| self.allocator.free(ls.name);
        self.lang_list.deinit(self.allocator);
        self.sorted_files.deinit(self.allocator);
        self.sorted_binaries.deinit(self.allocator);
        self.allocator.free(self.generated_at_str);
        self.allocator.free(self.date_str);
    }
};

// ============================================================
// Tests
// ============================================================

test "ReportData.init aggregates language stats" {
    const alloc = std.testing.allocator;

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();
    try file_entries.put("main.zig", .{ .path = "main.zig", .content = @constCast(""), .size = 100, .mtime = 0, .extension = ".zig", .line_count = 10 });
    try file_entries.put("lib.zig", .{ .path = "lib.zig", .content = @constCast(""), .size = 200, .mtime = 0, .extension = ".zig", .line_count = 20 });
    try file_entries.put("app.js", .{ .path = "app.js", .content = @constCast(""), .size = 50, .mtime = 0, .extension = ".js", .line_count = 5 });

    var binary_entries = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries.deinit();

    var data = try ReportData.init(alloc, &file_entries, &binary_entries, null);
    defer data.deinit();

    try std.testing.expectEqual(@as(usize, 35), data.total_lines);
    try std.testing.expectEqual(@as(u64, 350), data.total_size);
    try std.testing.expectEqual(@as(usize, 2), data.lang_list.items.len);

    // lang_list is sorted by name: "js" < "zig"
    try std.testing.expectEqualStrings("js", data.lang_list.items[0].name);
    try std.testing.expectEqual(@as(usize, 1), data.lang_list.items[0].files);
    try std.testing.expectEqualStrings("zig", data.lang_list.items[1].name);
    try std.testing.expectEqual(@as(usize, 2), data.lang_list.items[1].files);
}

test "ReportData.init sorts files by path" {
    const alloc = std.testing.allocator;

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();
    try file_entries.put("z_last.zig", .{ .path = "z_last.zig", .content = @constCast(""), .size = 0, .mtime = 0, .extension = ".zig", .line_count = 0 });
    try file_entries.put("a_first.zig", .{ .path = "a_first.zig", .content = @constCast(""), .size = 0, .mtime = 0, .extension = ".zig", .line_count = 0 });

    var binary_entries = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries.deinit();

    var data = try ReportData.init(alloc, &file_entries, &binary_entries, null);
    defer data.deinit();

    try std.testing.expectEqual(@as(usize, 2), data.sorted_files.items.len);
    try std.testing.expectEqualStrings("a_first.zig", data.sorted_files.items[0].path);
    try std.testing.expectEqualStrings("z_last.zig", data.sorted_files.items[1].path);
}

test "ReportData.init handles empty entries" {
    const alloc = std.testing.allocator;

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();
    var binary_entries = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries.deinit();

    var data = try ReportData.init(alloc, &file_entries, &binary_entries, null);
    defer data.deinit();

    try std.testing.expectEqual(@as(usize, 0), data.sorted_files.items.len);
    try std.testing.expectEqual(@as(usize, 0), data.sorted_binaries.items.len);
    try std.testing.expectEqual(@as(usize, 0), data.lang_list.items.len);
    try std.testing.expectEqual(@as(usize, 0), data.total_lines);
    try std.testing.expectEqual(@as(u64, 0), data.total_size);
    try std.testing.expect(data.generated_at_str.len > 0);
}
