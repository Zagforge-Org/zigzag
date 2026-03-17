const std = @import("std");
const ScanResult = @import("./scan.zig").ScanResult;
const nsElapsed = @import("./scan.zig").nsElapsed;
const Config = @import("../config/config.zig").Config;
const Pool = @import("../../../workers/pool.zig").Pool;
const report = @import("../report.zig");
const lg = @import("../../../utils/utils.zig");
const Logger = lg.Logger;
const BenchResult = @import("../bench.zig").BenchResult;

/// File size in bytes, or 0 on error.
fn fileSizeOf(path: []const u8) u64 {
    const stat = std.fs.cwd().statFile(path) catch return 0;
    return stat.size;
}

/// Write all configured reports for a completed scan result.
/// `verbose`: when false, phase/success lines are suppressed (TTY uses final summary instead).
pub fn writePathReports(
    result: *const ScanResult,
    cfg: *const Config,
    pool: *Pool,
    allocator: std.mem.Allocator,
    logger: ?*Logger,
    bench: ?*BenchResult,
    verbose: bool,
) !void {
    _ = pool; // reserved for future use

    if (verbose) lg.printStep("{s}", .{std.fs.path.basename(result.root_path)});

    const output_filename: []const u8 = if (cfg.output) |o| o else "report.md";
    const md_path = try report.resolveOutputPath(allocator, cfg, result.root_path, output_filename);
    defer allocator.free(md_path);

    // HTML content sidecar — timing not tracked (see write-html block below).
    if (cfg.html_output) {
        const html_path_for_content = try report.deriveHtmlPath(allocator, md_path);
        defer allocator.free(html_path_for_content);
        const content_dir = try report.deriveContentDir(allocator, html_path_for_content);
        defer allocator.free(content_dir);
        try report.writeContentFiles(&result.file_entries, content_dir, allocator);
        if (verbose) lg.printSuccess("Content dir:   {s}/", .{content_dir});
        if (logger) |l| l.log("Content files written: {s}/", .{content_dir});
    }

    // Aggregate — timer starts after content sidecar.
    const t_agg = std.time.nanoTimestamp();
    if (verbose) lg.printPhaseStart("Aggregating...", .{});
    var report_data = report.ReportData.init(allocator, &result.file_entries, &result.binary_entries, cfg.timezone_offset) catch |err| {
        if (verbose) lg.printPhaseDone(nsElapsed(t_agg), "", .{});
        return err;
    };
    defer report_data.deinit();
    if (bench) |b| b.aggregate_ns += nsElapsed(t_agg);
    if (verbose) lg.printPhaseDone(nsElapsed(t_agg), "", .{});

    // write-md
    const t_md = std.time.nanoTimestamp();
    if (verbose) lg.printPhaseStart("Writing report...", .{});
    report.writeReport(&report_data, &result.file_entries, md_path, result.root_path, cfg, allocator) catch |err| {
        if (verbose) lg.printPhaseDone(nsElapsed(t_md), "", .{});
        return err;
    };
    if (bench) |b| {
        b.write_md_ns += nsElapsed(t_md);
        b.md_bytes += fileSizeOf(md_path);
    }
    if (verbose) lg.printPhaseDone(nsElapsed(t_md), "", .{});
    if (verbose) lg.printSuccess("Report written: {s}", .{md_path});
    if (logger) |l| l.log("Report written: {s}", .{md_path});

    // write-json
    if (cfg.json_output) {
        const json_path = try report.deriveJsonPath(allocator, md_path);
        defer allocator.free(json_path);
        const t_json = std.time.nanoTimestamp();
        if (verbose) lg.printPhaseStart("Writing JSON...", .{});
        report.writeJsonReport(&report_data, json_path, result.root_path, cfg, allocator) catch |err| {
            if (verbose) lg.printPhaseDone(nsElapsed(t_json), "", .{});
            return err;
        };
        if (bench) |b| {
            b.write_json_ns += nsElapsed(t_json);
            b.json_bytes += fileSizeOf(json_path);
        }
        if (verbose) lg.printPhaseDone(nsElapsed(t_json), "", .{});
        if (verbose) lg.printSuccess("JSON report: {s}", .{json_path});
        if (logger) |l| l.log("JSON report written: {s}", .{json_path});
    }

    // write-html
    if (cfg.html_output) {
        const html_path = try report.deriveHtmlPath(allocator, md_path);
        defer allocator.free(html_path);
        const t_html = std.time.nanoTimestamp();
        if (verbose) lg.printPhaseStart("Writing HTML...", .{});
        report.writeHtmlReport(&report_data, html_path, result.root_path, cfg, allocator) catch |err| {
            if (verbose) lg.printPhaseDone(nsElapsed(t_html), "", .{});
            return err;
        };
        if (bench) |b| {
            b.write_html_ns += nsElapsed(t_html);
            b.html_bytes += fileSizeOf(html_path);
        }
        if (verbose) lg.printPhaseDone(nsElapsed(t_html), "", .{});
        if (verbose) lg.printSuccess("HTML report: {s}", .{html_path});
        if (logger) |l| l.log("HTML report written: {s}", .{html_path});
    }

    // write-llm
    if (cfg.llm_report) {
        const llm_path = try report.deriveLlmPath(allocator, md_path);
        defer allocator.free(llm_path);
        const t_llm = std.time.nanoTimestamp();
        if (verbose) lg.printPhaseStart("Writing LLM report...", .{});
        report.writeLlmReport(&report_data, result.binary_entries.count(), llm_path, result.root_path, cfg, cfg.llm_chunk_size, allocator) catch |err| {
            if (verbose) lg.printPhaseDone(nsElapsed(t_llm), "", .{});
            return err;
        };
        if (bench) |b| {
            b.write_llm_ns += nsElapsed(t_llm);
            b.llm_bytes += fileSizeOf(llm_path);
        }
        if (verbose) lg.printPhaseDone(nsElapsed(t_llm), "", .{});
        if (verbose) lg.printSuccess("LLM report: {s}", .{llm_path});
        if (logger) |l| l.log("LLM report written: {s}", .{llm_path});
    }

    const sv = result.stats.getSummary();
    lg.printSummary(.{ .path = result.root_path, .total = sv.total, .source = sv.source, .cached = sv.cached, .fresh = sv.processed, .binary = sv.binary, .ignored = sv.ignored });
    if (logger) |l| {
        l.log("Summary: total={d}, source={d}, cached={d}, fresh={d}, binary={d}, ignored={d}", .{
            sv.total, sv.source, sv.cached, sv.processed, sv.binary, sv.ignored,
        });
    }
}

/// Write the combined multi-path HTML report and its content sidecar.
/// Only called when html_output is true and at least 2 paths succeeded.
pub fn writeCombinedReports(
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
    try report.writeCombinedHtmlReport(path_data, combined_html_path, failed_paths, cfg, allocator);

    if (logger) |l| {
        l.log("Combined HTML written: {s}", .{combined_html_path});
        l.log("Combined content written: {s}/", .{combined_content_dir});
    }
}
