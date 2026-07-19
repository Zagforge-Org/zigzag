const std = @import("std");
const entries = @import("entries.zig");

const BinaryEntry = entries.BinaryEntry;
const JobEntry = entries.JobEntry;

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
