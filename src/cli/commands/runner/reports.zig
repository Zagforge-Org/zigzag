const std = @import("std");
const ScanResult = @import("./scan.zig").ScanResult;
const nsElapsed = @import("./scan.zig").nsElapsed;
const Config = @import("../config/config.zig").Config;
const Pool = @import("../../../workers/Pool.zig");
const report = @import("../report.zig");
const log = @import("../../../logger/Logger.zig");
const BenchResult = @import("../bench/BenchResult.zig");

/// File size in bytes, or 0 on error.
fn fileSizeOf(io: std.Io, path: []const u8) u64 {
    const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch return 0;
    return stat.size;
}

/// Write all configured reports for a completed scan result.
/// `verbose`: when false, phase/success lines are suppressed (TTY uses final summary instead).
pub fn writePathReports(
    io: std.Io,
    result: *const ScanResult,
    cfg: *const Config,
    pool: *Pool,
    allocator: std.mem.Allocator,
    bench: ?*BenchResult,
    verbose: bool,
) !void {
    _ = pool; // reserved for future use

    if (verbose) log.step(io, "{s}", .{std.fs.path.basename(result.root_path)});

    const output_filename: []const u8 = if (cfg.output) |o| o else "report.md";
    const md_path = try report.resolveOutputPath(io, allocator, cfg, result.root_path, output_filename);
    defer allocator.free(md_path);

    // HTML content sidecar — timing not tracked (see write-html block below).
    if (cfg.html_output) {
        const html_path_for_content = try report.deriveHtmlPath(allocator, md_path);
        defer allocator.free(html_path_for_content);
        const content_dir = try report.deriveContentDir(allocator, html_path_for_content);
        defer allocator.free(content_dir);
        try report.writeContentFiles(io, &result.file_entries, content_dir, allocator);
        if (verbose) log.success(io, "Content dir:   {s}/", .{content_dir});
        log.file(io, "Content files written: {s}/", .{content_dir});
    }

    // Aggregate — timer starts after content sidecar.
    const t_agg = std.Io.Timestamp.now(io, .real).nanoseconds;
    if (verbose) log.phaseStart(io, "Aggregating...", .{});
    var report_data = report.ReportData.init(io, allocator, &result.file_entries, &result.binary_entries, cfg.timezone_offset) catch |err| {
        if (verbose) log.phaseDone(io, nsElapsed(io, t_agg), "", .{});
        return err;
    };
    defer report_data.deinit();
    if (bench) |b| b.aggregate_ns += nsElapsed(io, t_agg);
    if (verbose) log.phaseDone(io, nsElapsed(io, t_agg), "", .{});

    // write-md
    const t_md = std.Io.Timestamp.now(io, .real).nanoseconds;
    if (verbose) log.phaseStart(io, "Writing report...", .{});
    report.writeReport(io, &report_data, &result.file_entries, md_path, result.root_path, cfg, allocator) catch |err| {
        if (verbose) log.phaseDone(io, nsElapsed(io, t_md), "", .{});
        return err;
    };
    if (bench) |b| {
        b.write_md_ns += nsElapsed(io, t_md);
        b.md_bytes += fileSizeOf(io, md_path);
    }
    if (verbose) log.phaseDone(io, nsElapsed(io, t_md), "", .{});
    if (verbose) log.success(io, "Report written: {s}", .{md_path});
    log.file(io, "Report written: {s}", .{md_path});

    // write-json
    if (cfg.json_output) {
        const json_path = try report.deriveJsonPath(allocator, md_path);
        defer allocator.free(json_path);
        const t_json = std.Io.Timestamp.now(io, .real).nanoseconds;
        if (verbose) log.phaseStart(io, "Writing JSON...", .{});
        report.writeJsonReport(io, &report_data, json_path, result.root_path, cfg, allocator) catch |err| {
            if (verbose) log.phaseDone(io, nsElapsed(io, t_json), "", .{});
            return err;
        };
        if (bench) |b| {
            b.write_json_ns += nsElapsed(io, t_json);
            b.json_bytes += fileSizeOf(io, json_path);
        }
        if (verbose) log.phaseDone(io, nsElapsed(io, t_json), "", .{});
        if (verbose) log.success(io, "JSON report: {s}", .{json_path});
        log.file(io, "JSON report written: {s}", .{json_path});
    }

    // write-html
    if (cfg.html_output) {
        const html_path = try report.deriveHtmlPath(allocator, md_path);
        defer allocator.free(html_path);
        const t_html = std.Io.Timestamp.now(io, .real).nanoseconds;
        if (verbose) log.phaseStart(io, "Writing HTML...", .{});
        report.writeHtmlReport(io, &report_data, html_path, result.root_path, cfg, allocator) catch |err| {
            if (verbose) log.phaseDone(io, nsElapsed(io, t_html), "", .{});
            return err;
        };
        if (bench) |b| {
            b.write_html_ns += nsElapsed(io, t_html);
            b.html_bytes += fileSizeOf(io, html_path);
        }
        if (verbose) log.phaseDone(io, nsElapsed(io, t_html), "", .{});
        if (verbose) log.success(io, "HTML report: {s}", .{html_path});
        log.file(io, "HTML report written: {s}", .{html_path});
    }

    // write-llm
    if (cfg.llm_report) {
        const llm_path = try report.deriveLlmPath(allocator, md_path);
        defer allocator.free(llm_path);
        const t_llm = std.Io.Timestamp.now(io, .real).nanoseconds;
        if (verbose) log.phaseStart(io, "Writing LLM report...", .{});
        report.writeLlmReport(io, &report_data, result.binary_entries.count(), llm_path, result.root_path, cfg, cfg.llm_chunk_size, allocator) catch |err| {
            if (verbose) log.phaseDone(io, nsElapsed(io, t_llm), "", .{});
            return err;
        };
        if (bench) |b| {
            b.write_llm_ns += nsElapsed(io, t_llm);
            b.llm_bytes += fileSizeOf(io, llm_path);
        }
        if (verbose) log.phaseDone(io, nsElapsed(io, t_llm), "", .{});
        if (verbose) log.success(io, "LLM report: {s}", .{llm_path});
        log.file(io, "LLM report written: {s}", .{llm_path});
    }

    const sv = result.stats.getSummary();
    log.summary(io, .{ .path = result.root_path, .total = sv.total, .source = sv.source, .cached = sv.cached, .fresh = sv.processed, .binary = sv.binary, .ignored = sv.ignored });
    log.file(io, "Summary: total={d}, source={d}, cached={d}, fresh={d}, binary={d}, ignored={d}", .{
        sv.total, sv.source, sv.cached, sv.processed, sv.binary, sv.ignored,
    });
}

/// Write the combined multi-path HTML report and its content sidecar.
/// Only called when html_output is true and at least 2 paths succeeded.
pub fn writeCombinedReports(
    io: std.Io,
    results: []const ScanResult,
    failed_paths: usize,
    cfg: *const Config,
    allocator: std.mem.Allocator,
) !void {
    const combined_html_path = try report.resolveCombinedHtmlPath(io, allocator, cfg);
    defer allocator.free(combined_html_path);

    const combined_content_dir = try report.resolveCombinedContentDir(io, allocator, cfg);
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
            io,
            allocator,
            &result.file_entries,
            &result.binary_entries,
            cfg.timezone_offset,
        );
        n_initialized += 1;
        path_data[i] = .{ .root_path = result.root_path, .data = &all_report_data[i] };
        content_paths[i] = .{ .root_path = result.root_path, .file_entries = &result.file_entries };
    }

    try report.writeCombinedContentFiles(io, content_paths, combined_content_dir, allocator);
    try report.writeCombinedHtmlReport(io, path_data, combined_html_path, failed_paths, cfg, allocator);

    log.file(io, "Combined HTML written: {s}", .{combined_html_path});
    log.file(io, "Combined content written: {s}/", .{combined_content_dir});
}
