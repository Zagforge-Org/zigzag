const std = @import("std");
const JobEntry = @import("../../../../jobs/entry.zig").JobEntry;
const BinaryEntry = @import("../../../../jobs/entry.zig").BinaryEntry;
const ReportData = @import("../aggregator.zig").ReportData;

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
