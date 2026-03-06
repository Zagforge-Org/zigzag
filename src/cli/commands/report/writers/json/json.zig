const std = @import("std");
const Config = @import("../../../config/config.zig").Config;
const JobEntry = @import("../../../../../jobs/entry.zig").JobEntry;
const BinaryEntry = @import("../../../../../jobs/entry.zig").BinaryEntry;
const ReportData = @import("../aggregator.zig").ReportData;

/// Serialize pre-aggregated data to a JSON report file alongside the markdown report.
pub fn writeJsonReport(
    data: *const ReportData,
    json_path: []const u8,
    root_path: []const u8,
    cfg: *const Config,
    allocator: std.mem.Allocator,
) !void {
    const output_filename = std.fs.path.basename(json_path);
    std.log.info("Building {s} for {s}...", .{ output_filename, root_path });

    var aw: std.io.Writer.Allocating = .init(allocator);
    defer aw.deinit();

    var ws: std.json.Stringify = .{ .writer = &aw.writer, .options = .{ .whitespace = .indent_2 } };
    try ws.beginObject();

    // meta
    try ws.objectField("meta");
    try ws.beginObject();
    try ws.objectField("version");
    try ws.write(cfg.version);
    try ws.objectField("generated_at_ns");
    try ws.write(std.time.nanoTimestamp());
    try ws.objectField("scanned_paths");
    try ws.beginArray();
    try ws.write(root_path);
    try ws.endArray();
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

    // files
    try ws.objectField("files");
    try ws.beginArray();
    for (data.sorted_files.items) |e| {
        try ws.beginObject();
        try ws.objectField("path");
        try ws.write(e.path);
        try ws.objectField("size");
        try ws.write(e.size);
        try ws.objectField("mtime_ns");
        try ws.write(e.mtime);
        try ws.objectField("extension");
        try ws.write(e.extension);
        try ws.objectField("language");
        try ws.write(e.getLanguage());
        try ws.objectField("lines");
        try ws.write(e.line_count);
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
        try ws.objectField("mtime_ns");
        try ws.write(b.mtime);
        try ws.objectField("extension");
        try ws.write(b.extension);
        try ws.endObject();
    }
    try ws.endArray();

    try ws.endObject();

    var json_file = try std.fs.cwd().createFile(json_path, .{ .truncate = true });
    defer json_file.close();
    try json_file.writeAll(aw.written());
}
