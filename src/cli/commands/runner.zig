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

/// Process a single directory path (one-shot mode)
fn processPath(
    cfg: *const Config,
    cache: ?*CacheImpl,
    path: []const u8,
    pool: *Pool,
    allocator: std.mem.Allocator,
    logger: ?*Logger,
) !void {
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

    // Auto-ignore the output directory to prevent scanning report artifacts
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
    defer {
        var it = file_entries.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.value_ptr.path);
            allocator.free(entry.value_ptr.content);
            allocator.free(entry.value_ptr.extension);
        }
        file_entries.deinit();
    }

    var binary_entries = std.StringHashMap(BinaryEntry).init(allocator);
    defer {
        var it = binary_entries.iterator();
        while (it.next()) |entry| {
            std.heap.page_allocator.free(entry.value_ptr.path);
            std.heap.page_allocator.free(entry.value_ptr.extension);
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

    // Build ReportData once; all writers share the pre-aggregated result.
    var report_data = try report.ReportData.init(allocator, &file_entries, &binary_entries, cfg.timezone_offset);
    defer report_data.deinit();

    try report.writeReport(&report_data, &file_entries, md_path, path, cfg, allocator);
    lg.printSuccess("Report written: {s}", .{md_path});
    if (logger) |l| l.log("Report written: {s}", .{md_path});

    if (cfg.json_output) {
        const json_path = try report.deriveJsonPath(allocator, md_path);
        defer allocator.free(json_path);
        try report.writeJsonReport(&report_data, json_path, path, cfg, allocator);
        lg.printSuccess("JSON report: {s}", .{json_path});
        if (logger) |l| l.log("JSON report written: {s}", .{json_path});
    }

    if (cfg.html_output) {
        const html_path = try report.deriveHtmlPath(allocator, md_path);
        defer allocator.free(html_path);
        try report.writeHtmlReport(&report_data, html_path, path, cfg, allocator);
        lg.printSuccess("HTML report: {s}", .{html_path});
        if (logger) |l| l.log("HTML report written: {s}", .{html_path});
    }

    if (cfg.llm_report) {
        const llm_path = try report.deriveLlmPath(allocator, md_path);
        defer allocator.free(llm_path);
        try report.writeLlmReport(&report_data, binary_entries.count(), llm_path, path, cfg, allocator);
        lg.printSuccess("LLM report: {s}", .{llm_path});
        if (logger) |l| l.log("LLM report written: {s}", .{llm_path});
    }

    const sv = stats.getSummary();
    lg.printSummary(path, sv.total, sv.source, sv.cached, sv.processed, sv.binary, sv.ignored);
    if (logger) |l| {
        l.log("Summary: total={d}, source={d}, cached={d}, fresh={d}, binary={d}, ignored={d}", .{
            sv.total, sv.source, sv.cached, sv.processed, sv.binary, sv.ignored,
        });
    }
}

/// Executes the runner command for all configured paths.
pub fn exec(cfg: *const Config, cache: ?*CacheImpl) !void {
    if (cfg.paths.items.len == 0) return;

    const allocator = std.heap.page_allocator;

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

    for (cfg.paths.items) |path| {
        processPath(cfg, cache, path, &pool, allocator, logger) catch |err| {
            switch (err) {
                error.NotADirectory => {
                    lg.printError("Path '{s}' is not a directory", .{path});
                    if (logger) |l| l.log("ERROR: Path '{s}' is not a directory", .{path});
                    return error.ErrorNotFound;
                },
                else => {
                    lg.printError("Unexpected error: {s}", .{@errorName(err)});
                    if (logger) |l| l.log("ERROR: {s}", .{@errorName(err)});
                },
            }
        };
    }

    lg.printSuccess("All paths processed!", .{});
    if (logger) |l| l.log("Done", .{});
}
