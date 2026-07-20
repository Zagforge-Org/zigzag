const std = @import("std");
const State = @import("State.zig");
const JobEntry = @import("../../../jobs/entries.zig").JobEntry;
const BinaryEntry = @import("../../../jobs/entries.zig").BinaryEntry;

test "State.removeFile removes file entry and frees memory" {
    var state: State = undefined;
    state.entries_mutex = .init;
    state.io = std.testing.io;
    state.defer_frees = false;
    state.graveyard_files = .empty;
    state.graveyard_binaries = .empty;
    state.allocator = std.testing.allocator;
    state.file_entries = std.StringHashMap(JobEntry).init(std.testing.allocator);
    defer state.file_entries.deinit();
    state.binary_entries = std.StringHashMap(BinaryEntry).init(std.testing.allocator);
    defer state.binary_entries.deinit();

    const path = try std.testing.allocator.dupe(u8, "src/target.zig");
    const content = try std.testing.allocator.dupe(u8, "pub fn run() void {}");
    const ext = try std.testing.allocator.dupe(u8, ".zig");

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
    state.entries_mutex = .init;
    state.io = std.testing.io;
    state.defer_frees = false;
    state.graveyard_files = .empty;
    state.graveyard_binaries = .empty;
    state.allocator = std.testing.allocator;
    state.file_entries = std.StringHashMap(JobEntry).init(std.testing.allocator);
    defer state.file_entries.deinit();
    state.binary_entries = std.StringHashMap(BinaryEntry).init(std.testing.allocator);
    defer state.binary_entries.deinit();

    state.removeFile("nonexistent/path.zig");
    try std.testing.expectEqual(@as(usize, 0), state.file_entries.count());
}

test "State.removeFile removes binary entry and frees memory" {
    var state: State = undefined;
    state.entries_mutex = .init;
    state.io = std.testing.io;
    state.defer_frees = false;
    state.graveyard_files = .empty;
    state.graveyard_binaries = .empty;
    state.allocator = std.testing.allocator;
    state.file_entries = std.StringHashMap(JobEntry).init(std.testing.allocator);
    defer state.file_entries.deinit();
    state.binary_entries = std.StringHashMap(BinaryEntry).init(std.testing.allocator);
    defer state.binary_entries.deinit();

    const path = try std.testing.allocator.dupe(u8, "assets/logo.png");
    const ext = try std.testing.allocator.dupe(u8, ".png");

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
    var state: State = undefined;
    state.entries_mutex = .init;
    state.io = std.testing.io;
    state.defer_frees = false;
    state.graveyard_files = .empty;
    state.graveyard_binaries = .empty;
    state.allocator = std.testing.allocator;
    state.file_entries = std.StringHashMap(JobEntry).init(std.testing.allocator);
    defer state.file_entries.deinit();
    state.binary_entries = std.StringHashMap(BinaryEntry).init(std.testing.allocator);
    defer state.binary_entries.deinit();

    const path1 = try std.testing.allocator.dupe(u8, "ambiguous");
    const content = try std.testing.allocator.dupe(u8, "data");
    const ext1 = try std.testing.allocator.dupe(u8, "");
    try state.file_entries.put(path1, JobEntry{
        .path = path1,
        .content = content,
        .size = 4,
        .mtime = 0,
        .extension = ext1,
        .line_count = 1,
    });

    const path2 = try std.testing.allocator.dupe(u8, "ambiguous");
    const ext2 = try std.testing.allocator.dupe(u8, "");
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

test "removeFile during a flush window retires the entry; endFlush frees it" {
    var state: State = undefined;
    state.entries_mutex = .init;
    state.io = std.testing.io;
    state.defer_frees = false;
    state.graveyard_files = .empty;
    state.graveyard_binaries = .empty;
    state.allocator = std.testing.allocator;
    state.file_entries = std.StringHashMap(JobEntry).init(std.testing.allocator);
    defer state.file_entries.deinit();
    state.binary_entries = std.StringHashMap(BinaryEntry).init(std.testing.allocator);
    defer state.binary_entries.deinit();
    defer state.graveyard_files.deinit(std.testing.allocator);
    defer state.graveyard_binaries.deinit(std.testing.allocator);

    const path = try std.testing.allocator.dupe(u8, "src/live.zig");
    const content = try std.testing.allocator.dupe(u8, "pub fn live() void {}");
    const ext = try std.testing.allocator.dupe(u8, ".zig");
    try state.file_entries.put(path, JobEntry{
        .path = path,
        .content = content,
        .size = 21,
        .mtime = 0,
        .extension = ext,
        .line_count = 1,
    });

    // Snapshot enters the deferred-free window.
    var data = try state.beginFlush(std.testing.allocator, null);
    defer data.deinit();
    const snapshot_content = data.sorted_files.items[0].content;

    // A concurrent event removes the file: entry must be retired, not freed,
    // so the snapshot's borrowed content stays readable.
    state.removeFile("src/live.zig");
    try std.testing.expectEqual(@as(usize, 0), state.file_entries.count());
    try std.testing.expectEqual(@as(usize, 1), state.graveyard_files.items.len);
    try std.testing.expectEqualStrings("pub fn live() void {}", snapshot_content);

    // Leaving the window releases the retired entry (testing allocator verifies).
    state.endFlush();
    try std.testing.expectEqual(@as(usize, 0), state.graveyard_files.items.len);
}
