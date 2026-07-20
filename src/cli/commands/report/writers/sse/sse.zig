//! SSE event payloads for watch-mode push updates.
//! The snapshot payloads reuse the shared dashboard schema writers in ../schema.zig so the browser
//! receives exactly the schema it embeds as __ZIGZAG_DATA__
//! Only the delta/delete events are SSE-specific.

const std = @import("std");
const Config = @import("../../../config/Config.zig");
const JobEntry = @import("../../../../../jobs/entries.zig").JobEntry;
const ReportData = @import("../aggregator.zig").ReportData;
const json = @import("../schema.zig");
const CombinedPathData = @import("../html/html.zig").CombinedPathData;

/// Build the full snapshot payload for a single-path dashboard, wrapped as
/// `{"report":{...}}`. Content is delivered separately via the sidecar.
pub fn buildSsePayload(
    data: *const ReportData,
    root_path: []const u8,
    cfg: *const Config,
    allocator: std.mem.Allocator,
) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();

    try aw.writer.writeAll("{\"report\":");
    var ws: std.json.Stringify = .{ .writer = &aw.writer, .options = .{} };
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
    try aw.writer.writeByte('}');

    return allocator.dupe(u8, aw.written());
}

/// Build the combined_update snapshot for the multi-path dashboard.
pub fn buildCombinedSsePayload(
    paths: []const CombinedPathData,
    failed_paths: usize,
    cfg: *const Config,
    allocator: std.mem.Allocator,
) ![]u8 {
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

    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    var ws: std.json.Stringify = .{ .writer = &aw.writer, .options = .{} };

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

    return allocator.dupe(u8, aw.written());
}

/// Build a delta payload for a single changed/created file:
/// `{"type":"file_update","path":...,"content":...,"meta":{...}}`.
pub fn buildFileDeltaPayload(
    allocator: std.mem.Allocator,
    entry: *const JobEntry,
) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
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

/// Build a delete event payload: `{"type":"file_delete","path":...}`.
pub fn buildFileDeletePayload(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
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
