const std = @import("std");
const State = @import("state.zig").State;
const SseServer = @import("server.zig").SseServer;
const Config = @import("../config/config.zig").Config;
const report = @import("../report.zig");

/// Build ReportData once and write all enabled report formats.
/// The optional sse_server receives the SSE payload when html_output is active.
pub fn writeAllReports(
    state: *State,
    cfg: *const Config,
    sse_server: ?*SseServer,
    allocator: std.mem.Allocator,
) void {
    var report_data = report.ReportData.init(
        allocator,
        &state.file_entries,
        &state.binary_entries,
        cfg.timezone_offset,
    ) catch |err| {
        std.log.err("Failed to aggregate report data for '{s}': {s}", .{ state.root_path, @errorName(err) });
        return;
    };
    defer report_data.deinit();

    report.writeReport(&report_data, &state.file_entries, state.md_path, state.root_path, cfg, allocator) catch |err| {
        std.log.err("Failed to write report for '{s}': {s}", .{ state.root_path, @errorName(err) });
    };

    if (cfg.json_output) {
        const json_path = report.deriveJsonPath(allocator, state.md_path) catch null;
        if (json_path) |jp| {
            defer allocator.free(jp);
            report.writeJsonReport(&report_data, jp, state.root_path, cfg, allocator) catch |err| {
                std.log.err("Failed to write JSON report for '{s}': {s}", .{ state.root_path, @errorName(err) });
            };
        }
    }

    if (cfg.html_output) {
        const html_path = report.deriveHtmlPath(allocator, state.md_path) catch null;
        if (html_path) |hp| {
            defer allocator.free(hp);
            report.writeHtmlReport(&report_data, hp, state.root_path, cfg, allocator) catch |err| {
                std.log.err("Failed to write HTML report for '{s}': {s}", .{ state.root_path, @errorName(err) });
            };
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
            report.writeLlmReport(&report_data, state.binary_entries.count(), lp, state.root_path, cfg, allocator) catch |err| {
                std.log.err("Failed to write LLM report for '{s}': {s}", .{ state.root_path, @errorName(err) });
            };
        }
    }
}
