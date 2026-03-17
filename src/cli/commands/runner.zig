const std = @import("std");
const scan_mod = @import("./runner/scan.zig");
const reports_mod = @import("./runner/reports.zig");
const Config = @import("config/config.zig").Config;
const CacheImpl = @import("../../cache/impl.zig").CacheImpl;
const Pool = @import("../../workers/pool.zig").Pool;
const lg = @import("../../utils/utils.zig");
const Logger = lg.Logger;

pub const BenchResult = @import("./bench.zig").BenchResult;

const ScanResult = scan_mod.ScanResult;
const nsElapsed = scan_mod.nsElapsed;

/// Executes the runner command for all configured paths.
pub fn exec(cfg: *const Config, cache: ?*CacheImpl, allocator: std.mem.Allocator, bench: ?*BenchResult) !void {
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

    const t_exec_start = std.time.nanoTimestamp();

    var pool = Pool{};
    try pool.init(.{
        .allocator = allocator,
        .n_jobs = cfg.n_threads,
    });
    defer pool.deinit();

    // Scan phase progress is suppressed on TTY because worker threads may print
    // to stderr between printPhaseStart and printPhaseDone, causing the cursor-up
    // rewrite (\x1B[1A) to overwrite a worker line instead of the scan line.
    // On non-TTY (piped/redirected), both calls emit clean text lines.
    const is_tty = std.posix.isatty(std.fs.File.stderr().handle);
    if (!is_tty) lg.printStep("Processing {d} path(s)...", .{cfg.paths.items.len});

    // Always collect timing data for the final summary (or for the external bench caller).
    var local_bench: BenchResult = .{};

    // Collect all scan results so we can write individual reports and then the
    // combined multi-path report (when html_output is true and >1 paths succeed).
    var all_results: std.ArrayList(ScanResult) = .empty;
    defer {
        for (all_results.items) |*r| r.deinit(allocator);
        all_results.deinit(allocator);
    }

    var failed_paths: usize = 0;

    // Collect display names for the final summary (basename of each successful path).
    var path_names: [128][]const u8 = undefined;
    var path_name_count: usize = 0;

    for (cfg.paths.items) |path| {
        const t_scan = std.time.nanoTimestamp();
        if (!is_tty) lg.printPhaseStart("Scanning {s}...", .{path});
        const scan_or_err = scan_mod.scanPath(cfg, cache, path, &pool, allocator, logger);
        const result: ScanResult = blk: {
            if (scan_or_err) |r| {
                if (!is_tty) lg.printPhaseDone(nsElapsed(t_scan), "{d} files", .{r.file_entries.count()});
                break :blk r;
            } else |err| {
                if (!is_tty) lg.printPhaseDone(nsElapsed(t_scan), "", .{});
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
            }
        };
        {
            const elapsed_scan = nsElapsed(t_scan);
            const summary = result.stats.getSummary();
            local_bench.scan_ns += elapsed_scan;
            local_bench.files_total += summary.total;
            local_bench.files_source += result.file_entries.count();
            local_bench.files_binary += result.binary_entries.count();
            local_bench.files_ignored += summary.ignored;
            if (bench) |b| {
                b.scan_ns += elapsed_scan;
                b.files_total += summary.total;
                b.files_source += result.file_entries.count();
                b.files_binary += result.binary_entries.count();
                b.files_ignored += summary.ignored;
            }
        }
        if (path_name_count < path_names.len) {
            path_names[path_name_count] = std.fs.path.basename(result.root_path);
            path_name_count += 1;
        }
        all_results.append(allocator, result) catch |err| {
            var r = result;
            r.deinit(allocator);
            return err;
        };
    }

    // verbose = true on non-TTY (keep existing per-path output) or when bench mode is active.
    const verbose = !is_tty or bench != null;

    for (all_results.items, 0..) |*result, i| {
        // Print a separator between writing blocks so each path is visually distinct.
        // Skip i==0: the last scan's trailing separator already provides the break.
        if (verbose and i > 0) lg.printSeparator();
        reports_mod.writePathReports(result, cfg, &pool, allocator, logger, &local_bench, verbose) catch |err| {
            lg.printError("Unexpected error: {s}", .{@errorName(err)});
            if (logger) |l| l.log("ERROR: {s}", .{@errorName(err)});
        };
    }

    // Write combined HTML dashboard when multiple paths produced results.
    const has_combined = cfg.html_output and all_results.items.len > 1;
    if (has_combined) {
        reports_mod.writeCombinedReports(all_results.items, failed_paths, cfg, allocator, logger) catch |err| {
            lg.printError("Combined report error: {s}", .{@errorName(err)});
            if (logger) |l| l.log("ERROR writing combined report: {s}", .{@errorName(err)});
        };
    }

    // Propagate local timing to external bench if provided.
    if (bench) |b| {
        b.aggregate_ns = local_bench.aggregate_ns;
        b.write_md_ns = local_bench.write_md_ns;
        b.write_json_ns = local_bench.write_json_ns;
        b.write_html_ns = local_bench.write_html_ns;
        b.write_llm_ns = local_bench.write_llm_ns;
        b.md_bytes = local_bench.md_bytes;
        b.json_bytes = local_bench.json_bytes;
        b.html_bytes = local_bench.html_bytes;
        b.llm_bytes = local_bench.llm_bytes;
    }

    if (is_tty and bench == null) {
        // Pretty interactive summary for terminal users.
        const summary_data = lg.FinalSummaryData{
            .total_ns = nsElapsed(t_exec_start),
            .scan_ns = local_bench.scan_ns,
            .aggregate_ns = local_bench.aggregate_ns,
            .write_md_ns = local_bench.write_md_ns,
            .write_json_ns = local_bench.write_json_ns,
            .write_html_ns = local_bench.write_html_ns,
            .write_llm_ns = local_bench.write_llm_ns,
            .files_total = local_bench.files_total,
            .md_bytes = local_bench.md_bytes,
            .path_names = path_names[0..path_name_count],
            .has_combined = has_combined,
        };
        lg.printFinalSummary(&summary_data);
    } else {
        lg.printSuccess("All paths processed!", .{});
    }
    if (logger) |l| l.log("Done", .{});
}
