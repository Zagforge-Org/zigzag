const std = @import("std");
const Config = @import("../../../config/config.zig").Config;
const JobEntry = @import("../../../../../jobs/entry.zig").JobEntry;
const BinaryEntry = @import("../../../../../jobs/entry.zig").BinaryEntry;
const ReportData = @import("../aggregator.zig").ReportData;

/// Build the SSE event payload for watch-mode push updates.
/// Returns JSON: {"report":{...},"content":"<content_map_json_string>"}
/// Caller must free the returned slice.
pub fn buildSsePayload(
    data: *const ReportData,
    root_path: []const u8,
    cfg: *const Config,
    allocator: std.mem.Allocator,
) ![]u8 {
    // Build report JSON (same structure as __ZIGZAG_DATA__)
    var report_aw: std.io.Writer.Allocating = .init(allocator);
    defer report_aw.deinit();
    var ws: std.json.Stringify = .{ .writer = &report_aw.writer, .options = .{} };
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
    {
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

    // files (metadata only)
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

    // Build content map JSON (same structure as __ZIGZAG_CONTENT__)
    var content_aw: std.io.Writer.Allocating = .init(allocator);
    defer content_aw.deinit();
    var cws: std.json.Stringify = .{ .writer = &content_aw.writer, .options = .{} };
    try cws.beginObject();
    for (data.sorted_files.items) |e| {
        try cws.objectField(e.path);
        try cws.write(e.content);
    }
    try cws.endObject();

    // Wrap into {"report":<report_json>,"content":<content_json_as_string>}
    var out: std.io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    try out.writer.writeAll("{\"report\":");
    try out.writer.writeAll(report_aw.written());
    try out.writer.writeAll(",\"content\":");
    var cs: std.json.Stringify = .{ .writer = &out.writer, .options = .{} };
    try cs.write(content_aw.written());
    try out.writer.writeByte('}');

    return allocator.dupe(u8, out.written());
}
