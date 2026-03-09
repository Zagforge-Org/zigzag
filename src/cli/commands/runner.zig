const std = @import("std");
const walk = @import("../../fs/walk.zig").Walk;
const walkerCallback = @import("../../walker/callback.zig").walkerCallback;
const Config = @import("config/config.zig").Config;
const FileContext = @import("../context.zig").FileContext;
const Pool = @import("../../workers/pool.zig").Pool;
const WaitGroup = @import("../../workers/wait_group.zig").WaitGroup;
const CacheImpl = @import("../../cache/impl.zig").CacheImpl;
const ProcessStats = @import("stats.zig").ProcessStats;
const JobEntry = @import("../../jobs/entry.zig").JobEntry;
const BinaryEntry = @import("../../jobs/entry.zig").BinaryEntry;
const WalkerCtx = @import("../../walker/context.zig").WalkerCtx;
const report = @import("report.zig");
const lg = @import("logger.zig");

const Logger = lg.Logger;

/// Owned result of scanning one path. Caller (exec) controls lifetime.
const ScanResult = struct {
    root_path: []const u8, // not owned — points into cfg.paths item
    file_entries: std.StringHashMap(JobEntry),
    binary_entries: std.StringHashMap(BinaryEntry),
    stats: ProcessStats,

    pub fn deinit(self: *ScanResult, allocator: std.mem.Allocator) void {
        var it = self.file_entries.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.value_ptr.path);
            allocator.free(entry.value_ptr.content);
            allocator.free(entry.value_ptr.extension);
        }
        self.file_entries.deinit();
        var bit = self.binary_entries.iterator();
        while (bit.next()) |entry| {
            allocator.free(entry.value_ptr.path);
            allocator.free(entry.value_ptr.extension);
        }
        self.binary_entries.deinit();
    }
};

/// Scan a single directory path and return collected entries. Caller owns the result.
fn scanPath(
    cfg: *const Config,
    cache: ?*CacheImpl,
    path: []const u8,
    pool: *Pool,
    allocator: std.mem.Allocator,
    logger: ?*Logger,
) !ScanResult {
    if (path.len != 0) {
        lg.printStep("Processing path: {s}", .{path});
        if (logger) |l| l.log("Processing path: {s}", .{path});
    }

    var dir = std.fs.cwd().openDir(path, .{}) catch {
        return error.NotADirectory;
    };
    defer dir.close();

    const output_filename: []const u8 = if (cfg.output) |o| o else "report.md";
    const md_path = try report.resolveOutputPath(allocator, cfg, path, output_filename);
    defer allocator.free(md_path);

    var file_ctx = FileContext{
        .ignore_list = .{},
        .md = undefined,
        .md_mutex = undefined,
    };
    defer file_ctx.ignore_list.deinit(allocator);

    // Auto-ignore the output directory to prevent scanning report artifacts.
    // This also excludes combined.html and combined-content.json which live
    // directly inside base_output_dir (not in a per-path subdirectory).
    const base_output_dir: []const u8 = if (cfg.output_dir) |d| d else "zigzag-reports";
    const output_dir_ignore = try allocator.dupe(u8, base_output_dir);
    try file_ctx.ignore_list.append(allocator, output_dir_ignore);

    const owned_md_path = try allocator.dupe(u8, md_path);
    try file_ctx.ignore_list.append(allocator, owned_md_path);

    if (cfg.json_output) {
        const json_ignore = try report.deriveJsonPath(allocator, md_path);
        try file_ctx.ignore_list.append(allocator, json_ignore);
    }

    if (cfg.html_output) {
        const html_ignore = try report.deriveHtmlPath(allocator, md_path);
        try file_ctx.ignore_list.append(allocator, html_ignore);
        // Also ignore the content sidecar so it doesn't appear as source
        const content_ignore = try report.deriveContentPath(allocator, html_ignore);
        try file_ctx.ignore_list.append(allocator, content_ignore);
    }

    if (cfg.llm_report) {
        const llm_ignore = try report.deriveLlmPath(allocator, md_path);
        try file_ctx.ignore_list.append(allocator, llm_ignore);
    }

    for (cfg.ignore_patterns.items) |pattern| {
        const owned_pattern = try allocator.dupe(u8, pattern);
        try file_ctx.ignore_list.append(allocator, owned_pattern);
    }

    var wg = WaitGroup.init();
    var stats = ProcessStats.init();

    var file_entries = std.StringHashMap(JobEntry).init(allocator);
    errdefer {
        var it = file_entries.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.value_ptr.path);
            allocator.free(entry.value_ptr.content);
            allocator.free(entry.value_ptr.extension);
        }
        file_entries.deinit();
    }

    var binary_entries = std.StringHashMap(BinaryEntry).init(allocator);
    errdefer {
        var it = binary_entries.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.value_ptr.path);
            allocator.free(entry.value_ptr.extension);
        }
        binary_entries.deinit();
    }

    var entries_mutex = std.Thread.Mutex{};

    var walker_ctx = WalkerCtx{
        .pool = pool,
        .wg = &wg,
        .file_ctx = &file_ctx,
        .cache = cache,
        .stats = &stats,
        .file_entries = &file_entries,
        .binary_entries = &binary_entries,
        .entries_mutex = &entries_mutex,
        .allocator = allocator,
    };

    const walker = try walk.init(allocator);
    const walk_ctx: ?*FileContext = @ptrCast(@alignCast(&walker_ctx));

    try walker.walkDir(path, walkerCallback, walk_ctx);
    wg.wait();

    // Log each processed file to the log file
    if (logger) |l| {
        var it = file_entries.iterator();
        while (it.next()) |entry| {
            l.log("  file: {s} ({d} bytes, {d} lines)", .{
                entry.value_ptr.path,
                entry.value_ptr.content.len,
                entry.value_ptr.line_count,
            });
        }
    }

    return ScanResult{
        .root_path = path,
        .file_entries = file_entries,
        .binary_entries = binary_entries,
        .stats = stats,
    };
}

/// Write all configured reports for a completed scan result.
fn writePathReports(
    result: *const ScanResult,
    cfg: *const Config,
    pool: *Pool,
    allocator: std.mem.Allocator,
    logger: ?*Logger,
) !void {
    _ = pool; // reserved for future use

    const output_filename: []const u8 = if (cfg.output) |o| o else "report.md";
    const md_path = try report.resolveOutputPath(allocator, cfg, result.root_path, output_filename);
    defer allocator.free(md_path);

    if (cfg.html_output) {
        const html_path_for_content = try report.deriveHtmlPath(allocator, md_path);
        defer allocator.free(html_path_for_content);
        const content_dir = try report.deriveContentDir(allocator, html_path_for_content);
        defer allocator.free(content_dir);
        try report.writeContentFiles(&result.file_entries, content_dir, allocator);
        lg.printSuccess("Content dir:   {s}/", .{content_dir});
        if (logger) |l| l.log("Content files written: {s}/", .{content_dir});
    }

    var report_data = try report.ReportData.init(allocator, &result.file_entries, &result.binary_entries, cfg.timezone_offset);
    defer report_data.deinit();

    try report.writeReport(&report_data, &result.file_entries, md_path, result.root_path, cfg, allocator);
    lg.printSuccess("Report written: {s}", .{md_path});
    if (logger) |l| l.log("Report written: {s}", .{md_path});

    if (cfg.json_output) {
        const json_path = try report.deriveJsonPath(allocator, md_path);
        defer allocator.free(json_path);
        try report.writeJsonReport(&report_data, json_path, result.root_path, cfg, allocator);
        lg.printSuccess("JSON report: {s}", .{json_path});
        if (logger) |l| l.log("JSON report written: {s}", .{json_path});
    }

    if (cfg.html_output) {
        const html_path = try report.deriveHtmlPath(allocator, md_path);
        defer allocator.free(html_path);
        try report.writeHtmlReport(&report_data, html_path, result.root_path, cfg, allocator);
        lg.printSuccess("HTML report: {s}", .{html_path});
        if (logger) |l| l.log("HTML report written: {s}", .{html_path});
    }

    if (cfg.llm_report) {
        const llm_path = try report.deriveLlmPath(allocator, md_path);
        defer allocator.free(llm_path);
        try report.writeLlmReport(&report_data, result.binary_entries.count(), llm_path, result.root_path, cfg, allocator);
        lg.printSuccess("LLM report: {s}", .{llm_path});
        if (logger) |l| l.log("LLM report written: {s}", .{llm_path});
    }

    const sv = result.stats.getSummary();
    lg.printSummary(result.root_path, sv.total, sv.source, sv.cached, sv.processed, sv.binary, sv.ignored);
    if (logger) |l| {
        l.log("Summary: total={d}, source={d}, cached={d}, fresh={d}, binary={d}, ignored={d}", .{
            sv.total, sv.source, sv.cached, sv.processed, sv.binary, sv.ignored,
        });
    }
}

/// Write the combined multi-path HTML report and its content sidecar.
/// Only called when html_output is true and at least 2 paths succeeded.
fn writeCombinedReports(
    results: []const ScanResult,
    failed_paths: usize,
    cfg: *const Config,
    allocator: std.mem.Allocator,
    logger: ?*Logger,
) !void {
    const combined_html_path = try report.resolveCombinedHtmlPath(allocator, cfg);
    defer allocator.free(combined_html_path);

    const combined_content_dir = try report.resolveCombinedContentDir(allocator, cfg);
    defer allocator.free(combined_content_dir);

    // Build per-path ReportData (cheap: aggregates in-memory entries).
    const all_report_data = try allocator.alloc(report.ReportData, results.len);
    var n_initialized: usize = 0;
    defer {
        for (all_report_data[0..n_initialized]) |*d| d.deinit();
        allocator.free(all_report_data);
    }

    const path_data = try allocator.alloc(report.CombinedPathData, results.len);
    defer allocator.free(path_data);

    const content_paths = try allocator.alloc(report.CombinedContentPath, results.len);
    defer allocator.free(content_paths);

    for (results, 0..) |*result, i| {
        all_report_data[i] = try report.ReportData.init(
            allocator,
            &result.file_entries,
            &result.binary_entries,
            cfg.timezone_offset,
        );
        n_initialized += 1;
        path_data[i] = .{ .root_path = result.root_path, .data = &all_report_data[i] };
        content_paths[i] = .{ .root_path = result.root_path, .file_entries = &result.file_entries };
    }

    try report.writeCombinedContentFiles(content_paths, combined_content_dir, allocator);
    lg.printSuccess("Combined content: {s}/", .{combined_content_dir});

    try report.writeCombinedHtmlReport(path_data, combined_html_path, failed_paths, cfg, allocator);
    lg.printSuccess("Combined HTML:    {s}", .{combined_html_path});

    if (logger) |l| {
        l.log("Combined HTML written: {s}", .{combined_html_path});
        l.log("Combined content written: {s}/", .{combined_content_dir});
    }
}

/// Executes the runner command for all configured paths.
pub fn exec(cfg: *const Config, cache: ?*CacheImpl, allocator: std.mem.Allocator) !void {
    if (cfg.paths.items.len == 0) return;

    // Set up file logger if --log is enabled
    var logger_storage: ?Logger = null;
    defer if (logger_storage) |*l| l.deinit();
    if (cfg.log) {
        const output_dir: []const u8 = if (cfg.output_dir) |d| d else "zigzag-reports";
        if (Logger.init(output_dir, allocator)) |l| {
            logger_storage = l;
        } else |err| {
            lg.printWarn("Could not create log file: {s}", .{@errorName(err)});
        }
    }
    const logger: ?*Logger = if (logger_storage) |*l| l else null;

    if (logger) |l| l.log("zigzag started — processing {d} path(s)", .{cfg.paths.items.len});

    var pool = Pool{};
    try pool.init(.{
        .allocator = allocator,
        .n_jobs = cfg.n_threads,
    });
    defer pool.deinit();

    lg.printStep("Processing {d} path(s)...", .{cfg.paths.items.len});

    // Collect all scan results so we can write individual reports and then the
    // combined multi-path report (when html_output is true and >1 paths succeed).
    var all_results: std.ArrayList(ScanResult) = .empty;
    defer {
        for (all_results.items) |*r| r.deinit(allocator);
        all_results.deinit(allocator);
    }

    var failed_paths: usize = 0;

    for (cfg.paths.items) |path| {
        const result = scanPath(cfg, cache, path, &pool, allocator, logger) catch |err| {
            switch (err) {
                error.NotADirectory => {
                    lg.printError("Path '{s}' is not a directory", .{path});
                    if (logger) |l| l.log("ERROR: Path '{s}' is not a directory", .{path});
                    return error.ErrorNotFound;
                },
                else => {
                    lg.printError("Unexpected error: {s}", .{@errorName(err)});
                    if (logger) |l| l.log("ERROR: {s}", .{@errorName(err)});
                    failed_paths += 1;
                    continue;
                },
            }
        };
        all_results.append(allocator, result) catch |err| {
            var r = result;
            r.deinit(allocator);
            return err;
        };
    }

    for (all_results.items) |*result| {
        writePathReports(result, cfg, &pool, allocator, logger) catch |err| {
            lg.printError("Unexpected error: {s}", .{@errorName(err)});
            if (logger) |l| l.log("ERROR: {s}", .{@errorName(err)});
        };
    }

    // Write combined HTML dashboard when multiple paths produced results.
    if (cfg.html_output and all_results.items.len > 1) {
        writeCombinedReports(all_results.items, failed_paths, cfg, allocator, logger) catch |err| {
            lg.printError("Combined report error: {s}", .{@errorName(err)});
            if (logger) |l| l.log("ERROR writing combined report: {s}", .{@errorName(err)});
        };
    }

    lg.printSuccess("All paths processed!", .{});
    if (logger) |l| l.log("Done", .{});
}
