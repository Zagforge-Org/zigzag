const std = @import("std");
const Config = @import("../../../config/config.zig").Config;
const JobEntry = @import("../../../../../jobs/entry.zig").JobEntry;
const BinaryEntry = @import("../../../../../jobs/entry.zig").BinaryEntry;
const ReportData = @import("../aggregator.zig").ReportData;

const dashboard_template = @embedFile("../../../../../templates/dashboard.html");

/// Write a self-contained HTML dashboard alongside the markdown report.
/// The template is loaded from src/templates/dashboard.html via @embedFile.
pub fn writeHtmlReport(
    data: *const ReportData,
    html_path: []const u8,
    root_path: []const u8,
    cfg: *const Config,
    allocator: std.mem.Allocator,
) !void {
    const output_filename = std.fs.path.basename(html_path);
    std.log.info("Building {s} for {s}...", .{ output_filename, root_path });

    // --- Split template on two markers ---
    // __ZIGZAG_DATA__    → report JSON (no file content) parsed eagerly
    // __ZIGZAG_CONTENT__ → content map {"path": "source"} loaded lazily
    const marker = "__ZIGZAG_DATA__";
    const content_marker = "__ZIGZAG_CONTENT__";
    const split_pos = std.mem.indexOf(u8, dashboard_template, marker) orelse
        return error.MissingTemplateMarker;
    const content_split_pos = std.mem.indexOf(u8, dashboard_template, content_marker) orelse
        return error.MissingTemplateMarker;

    // --- Build report JSON (metadata + stats, no content) ---
    var json_aw: std.io.Writer.Allocating = .init(allocator);
    defer json_aw.deinit();

    var ws: std.json.Stringify = .{ .writer = &json_aw.writer, .options = .{} };
    try ws.beginObject();

    // meta
    try ws.objectField("meta");
    try ws.beginObject();
    try ws.objectField("root_path");
    try ws.write(root_path);
    try ws.objectField("generated_at");
    try ws.write(data.generated_at_str);
    try ws.objectField("version");
    try ws.write(cfg.version);
    try ws.objectField("watch_mode");
    try ws.write(cfg.watch);
    if (cfg.watch and cfg.html_output) {
        const sse_url = try std.fmt.allocPrint(
            allocator,
            "http://127.0.0.1:{d}/__events",
            .{cfg.serve_port},
        );
        defer allocator.free(sse_url);
        try ws.objectField("sse_url");
        try ws.write(sse_url);
    }
    try ws.endObject();

    // summary
    try ws.objectField("summary");
    try ws.beginObject();
    try ws.objectField("source_files");
    try ws.write(data.sorted_files.items.len);
    try ws.objectField("binary_files");
    try ws.write(data.sorted_binaries.items.len);
    try ws.objectField("total_lines");
    try ws.write(data.total_lines);
    try ws.objectField("total_size_bytes");
    try ws.write(data.total_size);
    try ws.objectField("languages");
    try ws.beginArray();
    for (data.lang_list.items) |ls| {
        try ws.beginObject();
        try ws.objectField("name");
        try ws.write(ls.name);
        try ws.objectField("files");
        try ws.write(ls.files);
        try ws.objectField("lines");
        try ws.write(ls.lines);
        try ws.objectField("size_bytes");
        try ws.write(ls.size_bytes);
        try ws.endObject();
    }
    try ws.endArray();
    try ws.endObject();

    // files (metadata only; content goes in the separate content block)
    try ws.objectField("files");
    try ws.beginArray();
    for (data.sorted_files.items) |e| {
        try ws.beginObject();
        try ws.objectField("path");
        try ws.write(e.path);
        try ws.objectField("size");
        try ws.write(e.size);
        try ws.objectField("lines");
        try ws.write(e.line_count);
        try ws.objectField("language");
        try ws.write(e.getLanguage());
        try ws.endObject();
    }
    try ws.endArray();

    // binaries
    try ws.objectField("binaries");
    try ws.beginArray();
    for (data.sorted_binaries.items) |b| {
        try ws.beginObject();
        try ws.objectField("path");
        try ws.write(b.path);
        try ws.objectField("size");
        try ws.write(b.size);
        try ws.endObject();
    }
    try ws.endArray();

    try ws.endObject();

    // --- Build the content map {"path": "source", ...} ---
    var content_aw: std.io.Writer.Allocating = .init(allocator);
    defer content_aw.deinit();

    var cws: std.json.Stringify = .{ .writer = &content_aw.writer, .options = .{} };
    try cws.beginObject();
    for (data.sorted_files.items) |e| {
        try cws.objectField(e.path);
        try cws.write(e.content);
    }
    try cws.endObject();

    // Sanitize both payloads: </script> → <\/script> (valid JSON, HTML-safe)
    const json_raw = json_aw.written();
    const json_safe = try std.mem.replaceOwned(u8, allocator, json_raw, "</script>", "<\\/script>");
    defer allocator.free(json_safe);

    const content_raw = content_aw.written();
    const content_safe = try std.mem.replaceOwned(u8, allocator, content_raw, "</script>", "<\\/script>");
    defer allocator.free(content_safe);

    // Assemble: template_prefix + report_json + middle + content_json + suffix
    var aw: std.io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    try aw.writer.writeAll(dashboard_template[0..split_pos]);
    try aw.writer.writeAll(json_safe);
    try aw.writer.writeAll(dashboard_template[split_pos + marker.len .. content_split_pos]);
    try aw.writer.writeAll(content_safe);
    try aw.writer.writeAll(dashboard_template[content_split_pos + content_marker.len ..]);

    // Write to disk
    var html_file = try std.fs.cwd().createFile(html_path, .{ .truncate = true });
    defer html_file.close();
    try html_file.writeAll(aw.written());

    // In watch mode, write a tiny sidecar .stamp file containing only the
    // generated_at timestamp. The browser polls this cheap file instead of
    // the full HTML, and only fetches the full HTML on a change.
    if (cfg.watch) {
        const stamp_path = try std.fmt.allocPrint(allocator, "{s}.stamp", .{html_path});
        defer allocator.free(stamp_path);
        var stamp_file = try std.fs.cwd().createFile(stamp_path, .{ .truncate = true });
        defer stamp_file.close();
        try stamp_file.writeAll(data.generated_at_str);
    }
}
