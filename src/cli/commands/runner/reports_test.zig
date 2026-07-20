const std = @import("std");
const reports = @import("./reports.zig");
const scan = @import("./scan.zig");
const Config = @import("../config/Config.zig");
const Pool = @import("../../../workers/Pool.zig");
const Stats = @import("../stats.zig").Stats;
const JobEntry = @import("../../../jobs/entries.zig").JobEntry;
const BinaryEntry = @import("../../../jobs/entries.zig").BinaryEntry;

fn makeEmptyResult(alloc: std.mem.Allocator, root_path: []const u8) scan.ScanResult {
    return .{
        .root_path = root_path,
        .file_entries = std.StringHashMap(JobEntry).init(alloc),
        .binary_entries = std.StringHashMap(BinaryEntry).init(alloc),
        .stats = Stats.init(),
    };
}

test "writePathReports creates markdown report file" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = path_buf[0..try tmp.dir.realPathFile(std.testing.io, ".", &path_buf)];

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    cfg.output_dir = try alloc.dupe(u8, tmp_path);
    cfg._output_dir_allocated = true;

    var pool = Pool{};
    try pool.init(std.testing.io, .{ .allocator = alloc, .n_jobs = 1 });
    defer pool.deinit();

    var result = makeEmptyResult(alloc, tmp_path);
    defer result.deinit(alloc);

    try reports.writePathReports(std.testing.io, &result, &cfg, &pool, alloc, null, false);

    // resolveOutputPath produces {output_dir}/{basename(root_path)}/report.md
    const basename = std.fs.path.basename(tmp_path);
    const report_path = try std.fmt.allocPrint(alloc, "{s}/{s}/report.md", .{ tmp_path, basename });
    defer alloc.free(report_path);

    const stat = try std.Io.Dir.cwd().statFile(std.testing.io, report_path, .{});
    try std.testing.expect(stat.kind == .file);
}

test "writePathReports with scanned files produces non-empty report" {
    const alloc = std.testing.allocator;

    // Use CWD-relative dirs (not inside .zig-cache) so DEFAULT_SKIP_DIRS
    // doesn't filter out the test files. Use separate scan and output dirs so
    // the output path isn't a parent of the scanned files.
    var rand_scan: u64 = undefined;
    rand_scan = @truncate(@as(u96, @bitCast(std.Io.Timestamp.now(std.testing.io, .real).nanoseconds)));
    var scan_name_buf: [32]u8 = undefined;
    const scan_name = try std.fmt.bufPrint(&scan_name_buf, "zztest_scan_{x}", .{rand_scan});
    try std.Io.Dir.cwd().createDir(std.testing.io, scan_name, .default_dir);
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, scan_name) catch {};

    var rand_out: u64 = undefined;
    rand_out = @truncate(@as(u96, @bitCast(std.Io.Timestamp.now(std.testing.io, .real).nanoseconds)));
    var out_name_buf: [32]u8 = undefined;
    const out_name = try std.fmt.bufPrint(&out_name_buf, "zztest_out_{x}", .{rand_out});
    try std.Io.Dir.cwd().createDir(std.testing.io, out_name, .default_dir);
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, out_name) catch {};

    var scan_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const scan_path = scan_path_buf[0..try std.Io.Dir.cwd().realPathFile(std.testing.io, scan_name, &scan_path_buf)];
    var out_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const out_path = out_path_buf[0..try std.Io.Dir.cwd().realPathFile(std.testing.io, out_name, &out_path_buf)];

    var scan_dir = try std.Io.Dir.cwd().openDir(std.testing.io, scan_name, .{});
    defer scan_dir.close(std.testing.io);
    try scan_dir.writeFile(std.testing.io, .{ .sub_path = "hello.zig", .data = "const x = 42;\n" });

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    cfg.output_dir = try alloc.dupe(u8, out_path);
    cfg._output_dir_allocated = true;

    var pool = Pool{};
    try pool.init(std.testing.io, .{ .allocator = alloc, .n_jobs = 1 });
    defer pool.deinit();

    var scan_result = try scan.scanPath(std.testing.io, &cfg, null, scan_path, &pool, alloc);
    defer scan_result.deinit(alloc);

    try reports.writePathReports(std.testing.io, &scan_result, &cfg, &pool, alloc, null, false);

    const basename = std.fs.path.basename(scan_path);
    const report_path = try std.fmt.allocPrint(alloc, "{s}/{s}/report.md", .{ out_path, basename });
    defer alloc.free(report_path);

    const content = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, report_path, alloc, .limited(1024 * 1024));
    defer alloc.free(content);

    try std.testing.expect(content.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, content, "hello.zig") != null);
}
