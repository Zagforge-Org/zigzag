const std = @import("std");
const State = @import("state.zig").State;
const JobEntry = @import("../../../jobs/entry.zig").JobEntry;
const BinaryEntry = @import("../../../jobs/entry.zig").BinaryEntry;

test "State.removeFile removes file entry and frees memory" {
    const page_alloc = std.heap.page_allocator;

    var state: State = undefined;
    state.entries_mutex = .{};
    state.allocator = std.testing.allocator;
    state.file_entries = std.StringHashMap(JobEntry).init(std.testing.allocator);
    defer state.file_entries.deinit();
    state.binary_entries = std.StringHashMap(BinaryEntry).init(std.testing.allocator);
    defer state.binary_entries.deinit();

    const path = try page_alloc.dupe(u8, "src/target.zig");
    const content = try page_alloc.dupe(u8, "pub fn run() void {}");
    const ext = try page_alloc.dupe(u8, ".zig");

    try state.file_entries.put(path, JobEntry{
        .path = path,
        .content = content,
        .size = 20,
        .mtime = 0,
        .extension = ext,
        .line_count = 1,
    });

    try std.testing.expectEqual(@as(usize, 1), state.file_entries.count());
    state.removeFile("src/target.zig");
    try std.testing.expectEqual(@as(usize, 0), state.file_entries.count());
}

test "State.removeFile is a no-op for unknown paths" {
    var state: State = undefined;
    state.entries_mutex = .{};
    state.allocator = std.testing.allocator;
    state.file_entries = std.StringHashMap(JobEntry).init(std.testing.allocator);
    defer state.file_entries.deinit();
    state.binary_entries = std.StringHashMap(BinaryEntry).init(std.testing.allocator);
    defer state.binary_entries.deinit();

    state.removeFile("nonexistent/path.zig");
    try std.testing.expectEqual(@as(usize, 0), state.file_entries.count());
}

test "State.removeFile removes binary entry and frees memory" {
    const page_alloc = std.heap.page_allocator;

    var state: State = undefined;
    state.entries_mutex = .{};
    state.allocator = std.testing.allocator;
    state.file_entries = std.StringHashMap(JobEntry).init(std.testing.allocator);
    defer state.file_entries.deinit();
    state.binary_entries = std.StringHashMap(BinaryEntry).init(std.testing.allocator);
    defer state.binary_entries.deinit();

    const path = try page_alloc.dupe(u8, "assets/logo.png");
    const ext = try page_alloc.dupe(u8, ".png");

    try state.binary_entries.put(path, BinaryEntry{
        .path = path,
        .size = 1024,
        .mtime = 0,
        .extension = ext,
    });

    try std.testing.expectEqual(@as(usize, 1), state.binary_entries.count());
    state.removeFile("assets/logo.png");
    try std.testing.expectEqual(@as(usize, 0), state.binary_entries.count());
}

test "State.removeFile handles both file and binary entries for the same path" {
    const page_alloc = std.heap.page_allocator;

    var state: State = undefined;
    state.entries_mutex = .{};
    state.allocator = std.testing.allocator;
    state.file_entries = std.StringHashMap(JobEntry).init(std.testing.allocator);
    defer state.file_entries.deinit();
    state.binary_entries = std.StringHashMap(BinaryEntry).init(std.testing.allocator);
    defer state.binary_entries.deinit();

    const path1 = try page_alloc.dupe(u8, "ambiguous");
    const content = try page_alloc.dupe(u8, "data");
    const ext1 = try page_alloc.dupe(u8, "");
    try state.file_entries.put(path1, JobEntry{
        .path = path1,
        .content = content,
        .size = 4,
        .mtime = 0,
        .extension = ext1,
        .line_count = 1,
    });

    const path2 = try page_alloc.dupe(u8, "ambiguous");
    const ext2 = try page_alloc.dupe(u8, "");
    try state.binary_entries.put(path2, BinaryEntry{
        .path = path2,
        .size = 4,
        .mtime = 0,
        .extension = ext2,
    });

    state.removeFile("ambiguous");
    try std.testing.expectEqual(@as(usize, 0), state.file_entries.count());
    try std.testing.expectEqual(@as(usize, 0), state.binary_entries.count());
}
