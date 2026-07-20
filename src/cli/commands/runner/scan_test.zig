const std = @import("std");
const scan = @import("./scan.zig");
const Config = @import("../config/Config.zig");
const Pool = @import("../../../workers/Pool.zig");
const Stats = @import("../stats.zig").Stats;
const JobEntry = @import("../../../jobs/entries.zig").JobEntry;
const BinaryEntry = @import("../../../jobs/entries.zig").BinaryEntry;

// ── nsElapsed ─────────────────────────────────────────────────────────────────

test "nsElapsed clamps future timestamp to 0" {
    const future = std.Io.Timestamp.now(std.testing.io, .real).nanoseconds + 1_000_000_000_000;
    try std.testing.expectEqual(@as(u64, 0), scan.nsElapsed(std.testing.io, future));
}

test "nsElapsed returns positive for past timestamp" {
    const past = std.Io.Timestamp.now(std.testing.io, .real).nanoseconds - 1_000_000;
    try std.testing.expect(scan.nsElapsed(std.testing.io, past) > 0);
}

// ── ScanResult ────────────────────────────────────────────────────────────────

test "ScanResult.deinit on empty maps does not leak" {
    const alloc = std.testing.allocator;
    var result = scan.ScanResult{
        .root_path = "./",
        .file_entries = std.StringHashMap(JobEntry).init(alloc),
        .binary_entries = std.StringHashMap(BinaryEntry).init(alloc),
        .stats = Stats.init(),
    };
    result.deinit(alloc);
}

// ── scanPath ──────────────────────────────────────────────────────────────────

test "scanPath returns NotADirectory for a file path" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const f = try tmp.dir.createFile(std.testing.io, "not_a_dir.txt", .{});
    f.close(std.testing.io);

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const file_path = path_buf[0..try tmp.dir.realPathFile(std.testing.io, "not_a_dir.txt", &path_buf)];

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    var pool = Pool{};
    try pool.init(std.testing.io, .{ .allocator = alloc, .n_jobs = 1 });
    defer pool.deinit();

    const result = scan.scanPath(std.testing.io, &cfg, null, file_path, &pool, alloc);
    try std.testing.expectError(error.NotADirectory, result);
}

test "scanPath on empty directory returns zero entries" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = path_buf[0..try tmp.dir.realPathFile(std.testing.io, ".", &path_buf)];

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    var pool = Pool{};
    try pool.init(std.testing.io, .{ .allocator = alloc, .n_jobs = 1 });
    defer pool.deinit();

    var result = try scan.scanPath(std.testing.io, &cfg, null, dir_path, &pool, alloc);
    defer result.deinit(alloc);

    try std.testing.expectEqual(@as(usize, 0), result.file_entries.count());
    try std.testing.expectEqual(@as(usize, 0), result.binary_entries.count());
}

test "scanPath picks up source files in directory" {
    const alloc = std.testing.allocator;

    // Use a CWD-relative dir (not inside .zig-cache) so DEFAULT_SKIP_DIRS
    // doesn't filter out the test files. This matches the zztest_* pattern
    // used elsewhere in this codebase (e.g. conf/file_test.zig).
    var rand_int: u64 = undefined;
    rand_int = @truncate(@as(u96, @bitCast(std.Io.Timestamp.now(std.testing.io, .real).nanoseconds)));
    var dir_name_buf: [32]u8 = undefined;
    const dir_name = try std.fmt.bufPrint(&dir_name_buf, "zztest_{x}", .{rand_int});
    try std.Io.Dir.cwd().createDir(std.testing.io, dir_name, .default_dir);
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, dir_name) catch {};

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = path_buf[0..try std.Io.Dir.cwd().realPathFile(std.testing.io, dir_name, &path_buf)];

    var tmp_dir = try std.Io.Dir.cwd().openDir(std.testing.io, dir_name, .{});
    defer tmp_dir.close(std.testing.io);
    try tmp_dir.writeFile(std.testing.io, .{ .sub_path = "main.zig", .data = "const x = 1;\n" });
    try tmp_dir.writeFile(std.testing.io, .{ .sub_path = "readme.md", .data = "# Hello\n" });

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    var pool = Pool{};
    try pool.init(std.testing.io, .{ .allocator = alloc, .n_jobs = 1 });
    defer pool.deinit();

    var result = try scan.scanPath(std.testing.io, &cfg, null, dir_path, &pool, alloc);
    defer result.deinit(alloc);

    try std.testing.expectEqual(@as(usize, 2), result.file_entries.count());
}
