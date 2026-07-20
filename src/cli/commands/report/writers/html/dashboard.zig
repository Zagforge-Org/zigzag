//! Self-contained HTML dashboards.
//! Builds the JSON payload from the report data and splices it into the embedded template.
const std = @import("std");
const Config = @import("../../../config/Config.zig");
const ReportData = @import("../aggregator.zig").ReportData;
const json = @import("json.zig");

const dashboard_template = @embedFile("../../../../../templates/dashboard.html");
const combined_dashboard_template = @embedFile("../../../../../templates/combined-dashboard.html");

const MARKER = "__ZIGZAG_DATA__";

/// Splice the JSON payload into the template at MARKER and write the result to disk.
/// The `</script>` escape keeps the embedded JSON from closing the host <script> tag.
fn renderReport(io: std.Io, template: []const u8, json_body: []const u8, html_path: []const u8, allocator: std.mem.Allocator) !void {
    const split_pos = std.mem.indexOf(u8, template, MARKER) orelse
        return error.MissingTemplateMarker;

    const json_safe = try std.mem.replaceOwned(u8, allocator, json_body, "</script>", "<\\/script>");
    defer allocator.free(json_safe);

    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    try aw.writer.writeAll(template[0..split_pos]);
    try aw.writer.writeAll(json_safe);
    try aw.writer.writeAll(template[split_pos + MARKER.len ..]);

    var file = try std.Io.Dir.cwd().createFile(io, html_path, .{ .truncate = true });
    defer file.close(io);
    try file.writeStreamingAll(io, aw.written());
}

/// Write a self-contained HTML dashboard alongside the markdown report.
/// The template is loaded from src/templates/dashboard.html via @embedFile.
pub fn writeHtmlReport(
    io: std.Io,
    data: *const ReportData,
    html_path: []const u8,
    root_path: []const u8,
    cfg: *const Config,
    allocator: std.mem.Allocator,
) !void {
    var json_aw: std.Io.Writer.Allocating = .init(allocator);
    defer json_aw.deinit();
    var ws: std.json.Stringify = .{ .writer = &json_aw.writer, .options = .{} };

    try ws.beginObject();
    try (json.Meta{
        .ws = &ws,
        .allocator = allocator,
        .cfg = cfg,
        .root_path = root_path,
        .generated_at = data.generated_at_str,
    }).write();
    try (json.Summary{
        .ws = &ws,
        .source_files = data.sorted_files.items.len,
        .binary_files = data.sorted_binaries.items.len,
        .total_lines = data.total_lines,
        .total_size = data.total_size,
        .langs = data.lang_list.items,
    }).write();
    try (json.Files{ .ws = &ws, .items = data.sorted_files.items }).write();
    try (json.Binaries{ .ws = &ws, .items = data.sorted_binaries.items }).write();
    try ws.endObject();

    try renderReport(io, dashboard_template, json_aw.written(), html_path, allocator);
}

/// Per-path entry for the combined HTML report writer.
pub const CombinedPathData = struct {
    root_path: []const u8,
    data: *const ReportData,
};

/// Write a combined multi-path HTML dashboard using the combined-dashboard.html template.
pub fn writeCombinedHtmlReport(
    io: std.Io,
    paths: []const CombinedPathData,
    html_path: []const u8,
    failed_paths: usize,
    cfg: *const Config,
    allocator: std.mem.Allocator,
) !void {
    var total_files: usize = 0;
    var total_binary: usize = 0;
    var total_lines: usize = 0;
    var total_size: u64 = 0;
    for (paths) |p| {
        total_files += p.data.sorted_files.items.len;
        total_binary += p.data.sorted_binaries.items.len;
        total_lines += p.data.total_lines;
        total_size += p.data.total_size;
    }

    const generated_at: []const u8 = if (paths.len > 0) paths[0].data.generated_at_str else "unknown";

    var json_aw: std.Io.Writer.Allocating = .init(allocator);
    defer json_aw.deinit();
    var ws: std.json.Stringify = .{ .writer = &json_aw.writer, .options = .{} };

    try ws.beginObject();
    try (json.CombinedMeta{
        .ws = &ws,
        .allocator = allocator,
        .cfg = cfg,
        .path_count = paths.len,
        .failed_paths = failed_paths,
        .file_count = total_files,
        .generated_at = generated_at,
    }).write();
    try (json.Summary{
        .ws = &ws,
        .source_files = total_files,
        .binary_files = total_binary,
        .total_lines = total_lines,
        .total_size = total_size,
    }).write();

    try ws.objectField("paths");
    try ws.beginArray();
    for (paths) |p| {
        try ws.beginObject();
        try ws.objectField("root_path");
        try ws.write(p.root_path);
        try (json.Summary{
            .ws = &ws,
            .source_files = p.data.sorted_files.items.len,
            .binary_files = p.data.sorted_binaries.items.len,
            .total_lines = p.data.total_lines,
            .total_size = p.data.total_size,
            .langs = p.data.lang_list.items,
        }).write();
        try (json.Files{ .ws = &ws, .items = p.data.sorted_files.items, .root_path = p.root_path }).write();
        try (json.Binaries{ .ws = &ws, .items = p.data.sorted_binaries.items }).write();
        try ws.endObject();
    }
    try ws.endArray();
    try ws.endObject();

    try renderReport(io, combined_dashboard_template, json_aw.written(), html_path, allocator);
}
