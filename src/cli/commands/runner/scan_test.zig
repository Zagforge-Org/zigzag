const std = @import("std");
const scan = @import("./scan.zig");
const Config = @import("../config/config.zig").Config;
const Pool = @import("../../../workers/pool.zig").Pool;
const ProcessStats = @import("../stats.zig").ProcessStats;
const JobEntry = @import("../../../jobs/entry.zig").JobEntry;
const BinaryEntry = @import("../../../jobs/entry.zig").BinaryEntry;

// ── nsElapsed ─────────────────────────────────────────────────────────────────

test "nsElapsed clamps future timestamp to 0" {
    const future = std.time.nanoTimestamp() + 1_000_000_000_000;
    try std.testing.expectEqual(@as(u64, 0), scan.nsElapsed(future));
}

test "nsElapsed returns positive for past timestamp" {
    const past = std.time.nanoTimestamp() - 1_000_000;
    try std.testing.expect(scan.nsElapsed(past) > 0);
}

// ── ScanResult ────────────────────────────────────────────────────────────────

test "ScanResult.deinit on empty maps does not leak" {
    const alloc = std.testing.allocator;
    var result = scan.ScanResult{
        .root_path = "./",
        .file_entries = std.StringHashMap(JobEntry).init(alloc),
        .binary_entries = std.StringHashMap(BinaryEntry).init(alloc),
        .stats = ProcessStats.init(),
    };
    result.deinit(alloc);
}

// ── scanPath ──────────────────────────────────────────────────────────────────

test "scanPath returns NotADirectory for a file path" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const f = try tmp.dir.createFile("not_a_dir.txt", .{});
    f.close();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const file_path = try tmp.dir.realpath("not_a_dir.txt", &path_buf);

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    var pool = Pool{};
    try pool.init(.{ .allocator = alloc, .n_jobs = 1 });
    defer pool.deinit();

    const result = scan.scanPath(&cfg, null, file_path, &pool, alloc, null);
    try std.testing.expectError(error.NotADirectory, result);
}

test "scanPath on empty directory returns zero entries" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try tmp.dir.realpath(".", &path_buf);

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    var pool = Pool{};
    try pool.init(.{ .allocator = alloc, .n_jobs = 1 });
    defer pool.deinit();

    var result = try scan.scanPath(&cfg, null, dir_path, &pool, alloc, null);
    defer result.deinit(alloc);

    try std.testing.expectEqual(@as(usize, 0), result.file_entries.count());
    try std.testing.expectEqual(@as(usize, 0), result.binary_entries.count());
}

test "scanPath picks up source files in directory" {
    const alloc = std.testing.allocator;

    // Use /tmp to avoid DEFAULT_SKIP_DIRS filtering (.zig-cache is in the list
    // and std.testing.tmpDir creates dirs inside .zig-cache/tmp/).
    var rand_int: u64 = undefined;
    std.crypto.random.bytes(std.mem.asBytes(&rand_int));
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try std.fmt.bufPrint(&dir_buf, "/tmp/zigzag_scan_{x}", .{rand_int});
    try std.fs.makeDirAbsolute(dir_path);
    defer std.fs.deleteTreeAbsolute(dir_path) catch {};

    var tmp_dir = try std.fs.openDirAbsolute(dir_path, .{});
    defer tmp_dir.close();
    try tmp_dir.writeFile(.{ .sub_path = "main.zig", .data = "const x = 1;\n" });
    try tmp_dir.writeFile(.{ .sub_path = "readme.md", .data = "# Hello\n" });

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    var pool = Pool{};
    try pool.init(.{ .allocator = alloc, .n_jobs = 1 });
    defer pool.deinit();

    var result = try scan.scanPath(&cfg, null, dir_path, &pool, alloc, null);
    defer result.deinit(alloc);

    try std.testing.expectEqual(@as(usize, 2), result.file_entries.count());
}
