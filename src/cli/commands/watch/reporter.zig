const std = @import("std");
const State = @import("State.zig");
const Server = @import("Server.zig");
const Config = @import("../config/Config.zig");
const report = @import("../report.zig");
const log = @import("../../../logger/Logger.zig");
const Pool = @import("../../../workers/Pool.zig");

/// Write the combined multi-path HTML dashboard and its content sidecar.
/// No-op when html_output is false or fewer than 2 states are active.
/// changed_paths: slice of absolute file paths modified in the current debounce window.
///   - Empty slice -> write ALL combined content sidecar files (initial scan or post-overflow).
///   - Non-empty -> write only the listed paths' sidecars (incremental watch update).
/// After writing, broadcasts a "combined_update" SSE event when sse_server is non-null.
pub fn writeCombinedReport(
    io: std.Io,
    states: []*State,
    cfg: *const Config,
    sse_server: ?*Server,
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
        for (states[0..n_initialized]) |state| state.endFlush();
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
        // Snapshot under the entries lock; entry contents stay valid until the
        // deferred endFlush above releases the flush window.
        all_report_data[i] = state.beginFlush(allocator, cfg.timezone_offset) catch |err| {
            log.err(io, "Failed to init report data for '{s}': {s}", .{ state.root_path, @errorName(err) });
            return;
        };
        n_initialized += 1;
        path_data[i] = .{ .root_path = state.root_path, .data = &all_report_data[i] };
        content_paths[i] = .{ .root_path = state.root_path, .entries = all_report_data[i].sorted_files.items };
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

/// Write only the HTML dashboard (and watch stamp) for `state` — the minimum
/// needed for a usable dashboard at startup. The full report suite (md, json,
/// llm, sidecars) is deferred to the background flusher.
pub fn writeDashboardOnly(io: std.Io, state: *State, cfg: *const Config, allocator: std.mem.Allocator) void {
    if (!cfg.html_output) return;

    var report_data = state.beginFlush(allocator, cfg.timezone_offset) catch |err| {
        log.err(io, "Failed to aggregate report data for '{s}': {s}", .{ state.root_path, @errorName(err) });
        return;
    };
    defer state.endFlush();
    defer report_data.deinit();

    const html_path = report.deriveHtmlPath(allocator, state.md_path) catch return;
    defer allocator.free(html_path);

    report.writeHtmlReport(io, &report_data, html_path, state.root_path, cfg, allocator) catch |err| {
        log.err(io, "Failed to write HTML report for '{s}': {s}", .{ state.root_path, @errorName(err) });
        return;
    };
    if (cfg.watch) {
        report.writeStampFile(io, html_path, report_data.generated_at_str, allocator) catch {};
    }
}

/// Write only the combined multi-path dashboard HTML for fast first paint.
pub fn writeCombinedDashboardOnly(io: std.Io, states: []*State, cfg: *const Config, allocator: std.mem.Allocator) void {
    if (!cfg.html_output or states.len < 2) return;

    const combined_html_path = report.resolveCombinedHtmlPath(io, allocator, cfg) catch return;
    defer allocator.free(combined_html_path);

    const all_report_data = allocator.alloc(report.ReportData, states.len) catch return;
    var n_initialized: usize = 0;
    defer {
        for (states[0..n_initialized]) |state| state.endFlush();
        for (all_report_data[0..n_initialized]) |*d| d.deinit();
        allocator.free(all_report_data);
    }

    const path_data = allocator.alloc(report.CombinedPathData, states.len) catch return;
    defer allocator.free(path_data);

    for (states, 0..) |state, i| {
        all_report_data[i] = state.beginFlush(allocator, cfg.timezone_offset) catch return;
        n_initialized += 1;
        path_data[i] = .{ .root_path = state.root_path, .data = &all_report_data[i] };
    }

    report.writeCombinedHtmlReport(io, path_data, combined_html_path, 0, cfg, allocator) catch |err| {
        log.err(io, "Combined HTML write failed: {s}", .{@errorName(err)});
    };
}

/// Build ReportData once and write all enabled report formats.
/// The optional sse_server receives the SSE payload when html_output is active.
/// changed_paths: slice of absolute file paths modified in the current debounce window.
///   - Empty slice -> write ALL content sidecar files (initial scan or post-overflow).
///   - Non-empty -> write only the listed paths' sidecars (incremental watch update).
pub fn writeAllReports(
    io: std.Io,
    state: *State,
    cfg: *const Config,
    sse_server: ?*Server,
    changed_paths: []const []const u8,
    allocator: std.mem.Allocator,
    pool: ?*Pool,
) void {
    // Snapshot under the entries lock; the flush window keeps borrowed entry
    // contents alive while this (possibly background) write runs.
    var report_data = state.beginFlush(allocator, cfg.timezone_offset) catch |err| {
        log.err(io, "Failed to aggregate report data for '{s}': {s}", .{ state.root_path, @errorName(err) });
        return;
    };
    defer state.endFlush();
    defer report_data.deinit();

    report.writeReport(io, &report_data, state.md_path, state.root_path, cfg, allocator) catch |err| {
        log.err(io, "Failed to write report for '{s}': {s}", .{ state.root_path, @errorName(err) });
        return;
    };
    log.step(io, "Rebuilt: {s}", .{std.fs.path.basename(state.md_path)});

    if (cfg.json_output) writeJsonOutput(io, state, cfg, &report_data, allocator);
    if (cfg.html_output) writeHtmlOutput(io, state, cfg, &report_data, sse_server, changed_paths, allocator);
    if (cfg.llm_report) writeLlmOutput(io, state, cfg, &report_data, allocator, pool);
}

/// Write the JSON report sidecar for `state`.
fn writeJsonOutput(io: std.Io, state: *State, cfg: *const Config, report_data: *report.ReportData, allocator: std.mem.Allocator) void {
    const json_path = report.deriveJsonPath(allocator, state.md_path) catch return;
    defer allocator.free(json_path);
    report.writeJsonReport(io, report_data, json_path, state.root_path, cfg, allocator) catch |err| {
        log.err(io, "Failed to write JSON report for '{s}': {s}", .{ state.root_path, @errorName(err) });
    };
}

/// Write the HTML dashboard, content sidecars, watch stamp, and SSE report event.
fn writeHtmlOutput(
    io: std.Io,
    state: *State,
    cfg: *const Config,
    report_data: *report.ReportData,
    sse_server: ?*Server,
    changed_paths: []const []const u8,
    allocator: std.mem.Allocator,
) void {
    const html_path = report.deriveHtmlPath(allocator, state.md_path) catch return;
    defer allocator.free(html_path);

    report.writeHtmlReport(io, report_data, html_path, state.root_path, cfg, allocator) catch |err| {
        log.err(io, "Failed to write HTML report for '{s}': {s}", .{ state.root_path, @errorName(err) });
    };

    writeContentSidecars(io, report_data, html_path, changed_paths, allocator);

    // Write stamp AFTER content sidecar files are ready so stamp polling never
    // sees a new timestamp while content files are still being written.
    if (cfg.watch) {
        report.writeStampFile(io, html_path, report_data.generated_at_str, allocator) catch |err| {
            log.err(io, "stamp file write failed: {s}", .{@errorName(err)});
        };
    }

    if (sse_server) |srv| {
        const payload = report.buildSsePayload(report_data, state.root_path, cfg, allocator) catch null;
        if (payload) |p| {
            defer allocator.free(p);
            srv.broadcast(p);
        }
    }
}

/// Write content sidecars: only changed_paths, or all of them when the slice is empty.
fn writeContentSidecars(io: std.Io, report_data: *report.ReportData, html_path: []const u8, changed_paths: []const []const u8, allocator: std.mem.Allocator) void {
    const content_dir = report.deriveContentDir(allocator, html_path) catch return;
    defer allocator.free(content_dir);
    if (changed_paths.len > 0) {
        report.writeChangedContentFiles(io, report_data.sorted_files.items, changed_paths, content_dir, allocator) catch |err| {
            log.err(io, "content files write failed: {s}", .{@errorName(err)});
        };
    } else {
        report.writeContentFiles(io, report_data.sorted_files.items, content_dir, allocator) catch |err| {
            log.err(io, "content files write failed: {s}", .{@errorName(err)});
        };
    }
}

/// Write the LLM report sidecar for `state`.
fn writeLlmOutput(io: std.Io, state: *State, cfg: *const Config, report_data: *report.ReportData, allocator: std.mem.Allocator, pool: ?*Pool) void {
    const llm_path = report.deriveLlmPath(allocator, state.md_path) catch return;
    defer allocator.free(llm_path);
    report.writeLlmReport(io, report_data, report_data.sorted_binaries.items.len, llm_path, state.root_path, cfg, cfg.llm_chunk_size, allocator, pool, &state.llm_memo) catch |err| {
        log.err(io, "Failed to write LLM report for '{s}': {s}", .{ state.root_path, @errorName(err) });
    };
}
