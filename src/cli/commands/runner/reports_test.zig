const std = @import("std");
const reports = @import("./reports.zig");
const scan = @import("./scan.zig");
const Config = @import("../config/config.zig").Config;
const Pool = @import("../../../workers/pool.zig").Pool;
const ProcessStats = @import("../stats.zig").ProcessStats;
const JobEntry = @import("../../../jobs/entry.zig").JobEntry;
const BinaryEntry = @import("../../../jobs/entry.zig").BinaryEntry;

fn makeEmptyResult(alloc: std.mem.Allocator, root_path: []const u8) scan.ScanResult {
    return .{
        .root_path = root_path,
        .file_entries = std.StringHashMap(JobEntry).init(alloc),
        .binary_entries = std.StringHashMap(BinaryEntry).init(alloc),
        .stats = ProcessStats.init(),
    };
}

test "writePathReports creates markdown report file" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    cfg.output_dir = try alloc.dupe(u8, tmp_path);
    cfg._output_dir_allocated = true;

    var pool = Pool{};
    try pool.init(.{ .allocator = alloc, .n_jobs = 1 });
    defer pool.deinit();

    var result = makeEmptyResult(alloc, tmp_path);
    defer result.deinit(alloc);

    try reports.writePathReports(&result, &cfg, &pool, alloc, null, null, false);

    // resolveOutputPath produces {output_dir}/{basename(root_path)}/report.md
    const basename = std.fs.path.basename(tmp_path);
    const report_path = try std.fmt.allocPrint(alloc, "{s}/{s}/report.md", .{ tmp_path, basename });
    defer alloc.free(report_path);

    const stat = try std.fs.cwd().statFile(report_path);
    try std.testing.expect(stat.kind == .file);
}

test "writePathReports with scanned files produces non-empty report" {
    const alloc = std.testing.allocator;

    // Use CWD-relative dirs (not inside .zig-cache) so DEFAULT_SKIP_DIRS
    // doesn't filter out the test files. Use separate scan and output dirs so
    // the output path isn't a parent of the scanned files.
    var rand_scan: u64 = undefined;
    std.crypto.random.bytes(std.mem.asBytes(&rand_scan));
    var scan_name_buf: [32]u8 = undefined;
    const scan_name = try std.fmt.bufPrint(&scan_name_buf, "zztest_scan_{x}", .{rand_scan});
    try std.fs.cwd().makeDir(scan_name);
    defer std.fs.cwd().deleteTree(scan_name) catch {};

    var rand_out: u64 = undefined;
    std.crypto.random.bytes(std.mem.asBytes(&rand_out));
    var out_name_buf: [32]u8 = undefined;
    const out_name = try std.fmt.bufPrint(&out_name_buf, "zztest_out_{x}", .{rand_out});
    try std.fs.cwd().makeDir(out_name);
    defer std.fs.cwd().deleteTree(out_name) catch {};

    var scan_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const scan_path = try std.fs.cwd().realpath(scan_name, &scan_path_buf);
    var out_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const out_path = try std.fs.cwd().realpath(out_name, &out_path_buf);

    var scan_dir = try std.fs.cwd().openDir(scan_name, .{});
    defer scan_dir.close();
    try scan_dir.writeFile(.{ .sub_path = "hello.zig", .data = "const x = 42;\n" });

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    cfg.output_dir = try alloc.dupe(u8, out_path);
    cfg._output_dir_allocated = true;

    var pool = Pool{};
    try pool.init(.{ .allocator = alloc, .n_jobs = 1 });
    defer pool.deinit();

    var scan_result = try scan.scanPath(&cfg, null, scan_path, &pool, alloc, null);
    defer scan_result.deinit(alloc);

    try reports.writePathReports(&scan_result, &cfg, &pool, alloc, null, null, false);

    const basename = std.fs.path.basename(scan_path);
    const report_path = try std.fmt.allocPrint(alloc, "{s}/{s}/report.md", .{ out_path, basename });
    defer alloc.free(report_path);

    const content = try std.fs.cwd().readFileAlloc(alloc, report_path, 1024 * 1024);
    defer alloc.free(content);

    try std.testing.expect(content.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, content, "hello.zig") != null);
}
