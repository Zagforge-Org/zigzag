const std = @import("std");
const State = @import("state.zig").State;
const SseServer = @import("server.zig").SseServer;
const Config = @import("../config/Config.zig");
const report = @import("../report.zig");
const log = @import("../../../logger/Logger.zig");

/// Write the combined multi-path HTML dashboard and its content sidecar.
/// No-op when html_output is false or fewer than 2 states are active.
/// changed_paths: slice of absolute file paths modified in the current debounce window.
///   - Empty slice → write ALL combined content sidecar files (initial scan or post-overflow).
///   - Non-empty  → write only the listed paths' sidecars (incremental watch update).
/// After writing, broadcasts a "combined_update" SSE event when sse_server is non-null.
pub fn writeCombinedReport(
    io: std.Io,
    states: []*State,
    cfg: *const Config,
    sse_server: ?*SseServer,
    changed_paths: []const []const u8,
    allocator: std.mem.Allocator,
) void {
    if (!cfg.html_output or states.len < 2) return;

    const combined_html_path = report.resolveCombinedHtmlPath(io, allocator, cfg) catch |err| {
        log.err(io, "Failed to resolve combined HTML path: {s}", .{@errorName(err)});
        return;
    };
    defer allocator.free(combined_html_path);

    const combined_content_dir = report.resolveCombinedContentDir(io, allocator, cfg) catch |err| {
        log.err(io, "Failed to resolve combined content dir: {s}", .{@errorName(err)});
        return;
    };
    defer allocator.free(combined_content_dir);

    const all_report_data = allocator.alloc(report.ReportData, states.len) catch |err| {
        log.err(io, "Failed to alloc combined report data: {s}", .{@errorName(err)});
        return;
    };
    var n_initialized: usize = 0;
    defer {
        for (all_report_data[0..n_initialized]) |*d| d.deinit();
        allocator.free(all_report_data);
    }

    const path_data = allocator.alloc(report.CombinedPathData, states.len) catch |err| {
        log.err(io, "Failed to alloc combined path data: {s}", .{@errorName(err)});
        return;
    };
    defer allocator.free(path_data);

    const content_paths = allocator.alloc(report.CombinedContentPath, states.len) catch |err| {
        log.err(io, "Failed to alloc combined content paths: {s}", .{@errorName(err)});
        return;
    };
    defer allocator.free(content_paths);

    for (states, 0..) |state, i| {
        all_report_data[i] = report.ReportData.init(
            io,
            allocator,
            &state.file_entries,
            &state.binary_entries,
            cfg.timezone_offset,
        ) catch |err| {
            log.err(io, "Failed to init report data for '{s}': {s}", .{ state.root_path, @errorName(err) });
            return;
        };
        n_initialized += 1;
        path_data[i] = .{ .root_path = state.root_path, .data = &all_report_data[i] };
        content_paths[i] = .{ .root_path = state.root_path, .file_entries = &state.file_entries };
    }

    if (changed_paths.len > 0) {
        // Watch debounce: only write sidecars for files changed in this window.
        report.writeCombinedChangedContentFiles(io, content_paths, changed_paths, combined_content_dir, allocator) catch |err| {
            log.err(io, "Combined changed content write failed: {s}", .{@errorName(err)});
            return;
        };
    } else {
        // Initial scan or post-overflow: write all sidecars.
        report.writeCombinedContentFiles(io, content_paths, combined_content_dir, allocator) catch |err| {
            log.err(io, "Combined content write failed: {s}", .{@errorName(err)});
            return;
        };
    }

    report.writeCombinedHtmlReport(io, path_data, combined_html_path, 0, cfg, allocator) catch |err| {
        log.err(io, "Combined HTML write failed: {s}", .{@errorName(err)});
        return;
    };

    log.step(io, "Rebuilt: combined.html", .{});

    if (sse_server) |srv| {
        const payload = report.buildCombinedSsePayload(path_data, 0, cfg, allocator) catch null;
        if (payload) |p| {
            defer allocator.free(p);
            srv.broadcastCombined(p);
        }
    }
}

/// Build ReportData once and write all enabled report formats.
/// The optional sse_server receives the SSE payload when html_output is active.
/// changed_paths: slice of absolute file paths modified in the current debounce window.
///   - Empty slice → write ALL content sidecar files (initial scan or post-overflow).
///   - Non-empty  → write only the listed paths' sidecars (incremental watch update).
pub fn writeAllReports(
    io: std.Io,
    state: *State,
    cfg: *const Config,
    sse_server: ?*SseServer,
    changed_paths: []const []const u8,
    allocator: std.mem.Allocator,
) void {
    var report_data = report.ReportData.init(
        io,
        allocator,
        &state.file_entries,
        &state.binary_entries,
        cfg.timezone_offset,
    ) catch |err| {
        log.err(io, "Failed to aggregate report data for '{s}': {s}", .{ state.root_path, @errorName(err) });
        return;
    };
    defer report_data.deinit();

    report.writeReport(io, &report_data, &state.file_entries, state.md_path, state.root_path, cfg, allocator) catch |err| {
        log.err(io, "Failed to write report for '{s}': {s}", .{ state.root_path, @errorName(err) });
        return;
    };
    log.step(io, "Rebuilt: {s}", .{std.fs.path.basename(state.md_path)});

    if (cfg.json_output) {
        const json_path = report.deriveJsonPath(allocator, state.md_path) catch null;
        if (json_path) |jp| {
            defer allocator.free(jp);
            report.writeJsonReport(io, &report_data, jp, state.root_path, cfg, allocator) catch |err| {
                log.err(io, "Failed to write JSON report for '{s}': {s}", .{ state.root_path, @errorName(err) });
            };
        }
    }

    if (cfg.html_output) {
        const html_path = report.deriveHtmlPath(allocator, state.md_path) catch null;
        if (html_path) |hp| {
            defer allocator.free(hp);
            report.writeHtmlReport(io, &report_data, hp, state.root_path, cfg, allocator) catch |err| {
                log.err(io, "Failed to write HTML report for '{s}': {s}", .{ state.root_path, @errorName(err) });
            };
            const content_dir = report.deriveContentDir(allocator, hp) catch null;
            if (content_dir) |cd| {
                defer allocator.free(cd);
                if (changed_paths.len > 0) {
                    // Watch debounce: only write sidecars for files changed in this window.
                    report.writeChangedContentFiles(io, &state.file_entries, changed_paths, cd, allocator) catch |err| {
                        log.err(io, "content files write failed: {s}", .{@errorName(err)});
                    };
                } else {
                    // Initial scan or post-overflow: write all sidecars.
                    report.writeContentFiles(io, &state.file_entries, cd, allocator) catch |err| {
                        log.err(io, "content files write failed: {s}", .{@errorName(err)});
                    };
                }
            }
            // Write stamp AFTER content sidecar files are ready so stamp polling never
            // sees a new timestamp while content files are still being written.
            if (cfg.watch) {
                report.writeStampFile(io, hp, report_data.generated_at_str, allocator) catch |err| {
                    log.err(io, "stamp file write failed: {s}", .{@errorName(err)});
                };
            }
            if (sse_server) |srv| {
                const payload = report.buildSsePayload(&report_data, state.root_path, cfg, allocator) catch null;
                if (payload) |p| {
                    defer allocator.free(p);
                    srv.broadcast(p);
                }
            }
        }
    }

    if (cfg.llm_report) {
        const llm_path = report.deriveLlmPath(allocator, state.md_path) catch null;
        if (llm_path) |lp| {
            defer allocator.free(lp);
            report.writeLlmReport(io, &report_data, state.binary_entries.count(), lp, state.root_path, cfg, cfg.llm_chunk_size, allocator) catch |err| {
                log.err(io, "Failed to write LLM report for '{s}': {s}", .{ state.root_path, @errorName(err) });
            };
        }
    }
}
