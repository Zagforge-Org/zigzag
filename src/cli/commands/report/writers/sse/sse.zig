const std = @import("std");
const Config = @import("../../../config/config.zig").Config;
const JobEntry = @import("../../../../../jobs/entry.zig").JobEntry;
const BinaryEntry = @import("../../../../../jobs/entry.zig").BinaryEntry;
const ReportData = @import("../aggregator.zig").ReportData;
const CombinedPathData = @import("../html/html.zig").CombinedPathData;

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

    // Wrap into {"report":<report_json>}
    // Content is served separately via report-content.json (Phase 1 sidecar).
    var out: std.io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    try out.writer.writeAll("{\"report\":");
    try out.writer.writeAll(report_aw.written());
    try out.writer.writeByte('}');

    return allocator.dupe(u8, out.written());
}

pub const DeltaKind = enum { updated, created };

/// Build a small delta SSE payload for a single changed/created file.
/// Returns JSON: {"type":"file_update","path":"...","content":"...","meta":{...}}
/// Both .updated and .created map to "file_update" — browser handles both identically.
/// Caller must free.
pub fn buildFileDeltaPayload(
    allocator: std.mem.Allocator,
    entry: *const JobEntry,
    kind: DeltaKind,
) ![]u8 {
    _ = kind; // both map to "file_update"
    var aw: std.io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    var ws: std.json.Stringify = .{ .writer = &aw.writer, .options = .{} };
    try ws.beginObject();
    try ws.objectField("type");
    try ws.write("file_update");
    try ws.objectField("path");
    try ws.write(entry.path);
    try ws.objectField("content");
    try ws.write(entry.content);
    try ws.objectField("meta");
    try ws.beginObject();
    try ws.objectField("size");
    try ws.write(entry.size);
    try ws.objectField("lines");
    try ws.write(entry.line_count);
    try ws.objectField("language");
    try ws.write(entry.getLanguage());
    try ws.endObject();
    try ws.endObject();
    return allocator.dupe(u8, aw.written());
}

/// Build the SSE combined_update payload for the combined multi-path dashboard.
/// Returns raw JSON matching the CombinedReport TypeScript interface (no outer wrapper).
/// Caller must free the returned slice.
pub fn buildCombinedSsePayload(
    paths: []const CombinedPathData,
    failed_paths: usize,
    cfg: *const Config,
    allocator: std.mem.Allocator,
) ![]u8 {
    // Compute global totals
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

    const generated_at: []const u8 = if (paths.len > 0)
        paths[0].data.generated_at_str
    else
        "unknown";

    var aw: std.io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    var ws: std.json.Stringify = .{ .writer = &aw.writer, .options = .{} };
    try ws.beginObject();

    // meta
    try ws.objectField("meta");
    try ws.beginObject();
    try ws.objectField("combined");
    try ws.write(true);
    try ws.objectField("path_count");
    try ws.write(paths.len);
    try ws.objectField("successful_paths");
    try ws.write(paths.len);
    try ws.objectField("failed_paths");
    try ws.write(failed_paths);
    try ws.objectField("file_count");
    try ws.write(total_files);
    try ws.objectField("generated_at");
    try ws.write(generated_at);
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
    try ws.endObject(); // meta

    // global summary
    try ws.objectField("summary");
    try ws.beginObject();
    try ws.objectField("source_files");
    try ws.write(total_files);
    try ws.objectField("binary_files");
    try ws.write(total_binary);
    try ws.objectField("total_lines");
    try ws.write(total_lines);
    try ws.objectField("total_size_bytes");
    try ws.write(total_size);
    try ws.endObject(); // summary

    // paths array
    try ws.objectField("paths");
    try ws.beginArray();
    for (paths) |p| {
        try ws.beginObject();

        try ws.objectField("root_path");
        try ws.write(p.root_path);

        // per-path summary
        try ws.objectField("summary");
        try ws.beginObject();
        try ws.objectField("source_files");
        try ws.write(p.data.sorted_files.items.len);
        try ws.objectField("binary_files");
        try ws.write(p.data.sorted_binaries.items.len);
        try ws.objectField("total_lines");
        try ws.write(p.data.total_lines);
        try ws.objectField("total_size_bytes");
        try ws.write(p.data.total_size);
        try ws.objectField("languages");
        try ws.beginArray();
        for (p.data.lang_list.items) |ls| {
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
        try ws.endObject(); // per-path summary

        // files
        try ws.objectField("files");
        try ws.beginArray();
        for (p.data.sorted_files.items) |e| {
            try ws.beginObject();
            try ws.objectField("path");
            try ws.write(e.path);
            try ws.objectField("root_path");
            try ws.write(p.root_path);
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
        for (p.data.sorted_binaries.items) |b| {
            try ws.beginObject();
            try ws.objectField("path");
            try ws.write(b.path);
            try ws.objectField("size");
            try ws.write(b.size);
            try ws.endObject();
        }
        try ws.endArray();

        try ws.endObject(); // path entry
    }
    try ws.endArray(); // paths

    try ws.endObject(); // root

    return allocator.dupe(u8, aw.written());
}

/// Build a delete event payload: {"type":"file_delete","path":"..."}.
/// Caller must free.
pub fn buildFileDeletePayload(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var aw: std.io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    var ws: std.json.Stringify = .{ .writer = &aw.writer, .options = .{} };
    try ws.beginObject();
    try ws.objectField("type");
    try ws.write("file_delete");
    try ws.objectField("path");
    try ws.write(path);
    try ws.endObject();
    return allocator.dupe(u8, aw.written());
}
