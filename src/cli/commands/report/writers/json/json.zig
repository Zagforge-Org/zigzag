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

// ============================================================
// Tests
// ============================================================

test "writeJsonReport creates file with summary stats" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);
    const json_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.json" });
    defer alloc.free(json_path);

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();
    var binary_entries = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries.deinit();

    var cfg = Config.default(alloc);
    defer cfg.deinit();

    var data = try ReportData.init(alloc, &file_entries, &binary_entries, null);
    defer data.deinit();

    try writeJsonReport(&data, json_path, ".", &cfg, alloc);

    const content = try tmp.dir.readFileAlloc(alloc, "report.json", 1 << 20);
    defer alloc.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "\"source_files\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"binary_files\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"total_lines\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"total_size_bytes\"") != null);
}

test "writeJsonReport includes language stats" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);
    const json_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.json" });
    defer alloc.free(json_path);

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();
    try file_entries.put("main.zig", JobEntry{ .path = "main.zig", .content = @constCast(""), .size = 10, .mtime = 0, .extension = ".zig", .line_count = 5 });
    try file_entries.put("lib.zig", JobEntry{ .path = "lib.zig", .content = @constCast(""), .size = 20, .mtime = 0, .extension = ".zig", .line_count = 8 });
    try file_entries.put("config.json", JobEntry{ .path = "config.json", .content = @constCast(""), .size = 50, .mtime = 0, .extension = ".json", .line_count = 10 });

    var binary_entries = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries.deinit();

    var cfg = Config.default(alloc);
    defer cfg.deinit();

    var data = try ReportData.init(alloc, &file_entries, &binary_entries, null);
    defer data.deinit();

    try writeJsonReport(&data, json_path, ".", &cfg, alloc);

    const content = try tmp.dir.readFileAlloc(alloc, "report.json", 1 << 20);
    defer alloc.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "\"languages\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"zig\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"json\"") != null);
}

test "writeJsonReport files array is sorted by path" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);
    const json_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.json" });
    defer alloc.free(json_path);

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();
    try file_entries.put("z_last.zig", JobEntry{ .path = "z_last.zig", .content = @constCast(""), .size = 0, .mtime = 0, .extension = ".zig", .line_count = 0 });
    try file_entries.put("a_first.zig", JobEntry{ .path = "a_first.zig", .content = @constCast(""), .size = 0, .mtime = 0, .extension = ".zig", .line_count = 0 });

    var binary_entries = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries.deinit();

    var cfg = Config.default(alloc);
    defer cfg.deinit();

    var data = try ReportData.init(alloc, &file_entries, &binary_entries, null);
    defer data.deinit();

    try writeJsonReport(&data, json_path, ".", &cfg, alloc);

    const content = try tmp.dir.readFileAlloc(alloc, "report.json", 1 << 20);
    defer alloc.free(content);

    const pos_a = std.mem.indexOf(u8, content, "a_first.zig").?;
    const pos_z = std.mem.indexOf(u8, content, "z_last.zig").?;
    try std.testing.expect(pos_a < pos_z);
}

test "writeJsonReport meta includes scanned path and version" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);
    const json_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.json" });
    defer alloc.free(json_path);

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();
    var binary_entries = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries.deinit();

    var cfg = Config.default(alloc);
    defer cfg.deinit();

    var data = try ReportData.init(alloc, &file_entries, &binary_entries, null);
    defer data.deinit();

    try writeJsonReport(&data, json_path, "my/project", &cfg, alloc);

    const content = try tmp.dir.readFileAlloc(alloc, "report.json", 1 << 20);
    defer alloc.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "my/project") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"generated_at_ns\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"scanned_paths\"") != null);
}

