const std = @import("std");
const Config = @import("../../../config/config.zig").Config;
const JobEntry = @import("../../../../../jobs/entry.zig").JobEntry;
const BinaryEntry = @import("../../../../../jobs/entry.zig").BinaryEntry;
const ReportData = @import("../aggregator.zig").ReportData;

const dashboard_template = @embedFile("../../../../../templates/dashboard.html");
const combined_dashboard_template = @embedFile("../../../../../templates/combined-dashboard.html");

/// Write a self-contained HTML dashboard alongside the markdown report.
/// The template is loaded from src/templates/dashboard.html via @embedFile.
pub fn writeHtmlReport(
    data: *const ReportData,
    html_path: []const u8,
    root_path: []const u8,
    cfg: *const Config,
    allocator: std.mem.Allocator,
) !void {
    // --- Split template on __ZIGZAG_DATA__ marker ---
    const marker = "__ZIGZAG_DATA__";
    const split_pos = std.mem.indexOf(u8, dashboard_template, marker) orelse
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

    // Sanitize report payload: </script> → <\/script> (valid JSON, HTML-safe)
    const json_raw = json_aw.written();
    const json_safe = try std.mem.replaceOwned(u8, allocator, json_raw, "</script>", "<\\/script>");
    defer allocator.free(json_safe);

    // Assemble: template_prefix + report_json + rest_of_template
    var aw: std.io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    try aw.writer.writeAll(dashboard_template[0..split_pos]);
    try aw.writer.writeAll(json_safe);
    try aw.writer.writeAll(dashboard_template[split_pos + marker.len ..]);

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

/// Stream source content to a sidecar JSON file: {"path":"content",...}.
/// Iterates file_entries and JSON-encodes each key+value individually using
/// std.json.Stringify — O(max_file_size) peak RAM.
/// Caller must ensure the output directory exists.
pub fn writeContentJson(
    file_entries: *const std.StringHashMap(JobEntry),
    content_path: []const u8,
    allocator: std.mem.Allocator,
) !void {
    var file = try std.fs.cwd().createFile(content_path, .{ .truncate = true });
    defer file.close();

    try file.writeAll("{");
    var first = true;
    var it = file_entries.iterator();
    while (it.next()) |kv| {
        if (!first) try file.writeAll(",");
        first = false;

        // Encode key as JSON string using a small allocating writer
        var key_aw: std.io.Writer.Allocating = .init(allocator);
        defer key_aw.deinit();
        var kws: std.json.Stringify = .{ .writer = &key_aw.writer, .options = .{} };
        try kws.write(kv.key_ptr.*);
        try file.writeAll(key_aw.written());

        try file.writeAll(":");

        // Encode value as JSON string using a small allocating writer
        var val_aw: std.io.Writer.Allocating = .init(allocator);
        defer val_aw.deinit();
        var vws: std.json.Stringify = .{ .writer = &val_aw.writer, .options = .{} };
        try vws.write(kv.value_ptr.content);
        try file.writeAll(val_aw.written());
    }
    try file.writeAll("}");
}

/// Per-path entry for the combined content writer.
pub const CombinedContentPath = struct {
    root_path: []const u8,
    file_entries: *const std.StringHashMap(JobEntry),
};

/// Write a merged content sidecar for the combined report.
/// Keys use the format "{root_path}:{relative_path}" to prevent collisions
/// when two scanned paths contain files with the same relative path.
pub fn writeCombinedContentJson(
    paths: []const CombinedContentPath,
    content_path: []const u8,
    allocator: std.mem.Allocator,
) !void {
    var file = try std.fs.cwd().createFile(content_path, .{ .truncate = true });
    defer file.close();

    try file.writeAll("{");
    var first = true;
    for (paths) |p| {
        var it = p.file_entries.iterator();
        while (it.next()) |kv| {
            if (!first) try file.writeAll(",");
            first = false;

            // Key: "{root_path}:{path}"
            const combined_key = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ p.root_path, kv.key_ptr.* });
            defer allocator.free(combined_key);

            var key_aw: std.io.Writer.Allocating = .init(allocator);
            defer key_aw.deinit();
            var kws: std.json.Stringify = .{ .writer = &key_aw.writer, .options = .{} };
            try kws.write(combined_key);
            try file.writeAll(key_aw.written());

            try file.writeAll(":");

            var val_aw: std.io.Writer.Allocating = .init(allocator);
            defer val_aw.deinit();
            var vws: std.json.Stringify = .{ .writer = &val_aw.writer, .options = .{} };
            try vws.write(kv.value_ptr.content);
            try file.writeAll(val_aw.written());
        }
    }
    try file.writeAll("}");
}

/// Per-path entry for the combined HTML report writer.
pub const CombinedPathData = struct {
    root_path: []const u8,
    data: *const ReportData,
};

/// Write a combined multi-path HTML dashboard to html_path.
/// Uses the combined-dashboard.html template (separate from the single-path template).
pub fn writeCombinedHtmlReport(
    paths: []const CombinedPathData,
    html_path: []const u8,
    failed_paths: usize,
    cfg: *const Config,
    allocator: std.mem.Allocator,
) !void {
    const marker = "__ZIGZAG_DATA__";
    const split_pos = std.mem.indexOf(u8, combined_dashboard_template, marker) orelse
        return error.MissingTemplateMarker;

    // --- Compute global totals ---
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

    // --- Build combined JSON ---
    var json_aw: std.io.Writer.Allocating = .init(allocator);
    defer json_aw.deinit();

    var ws: std.json.Stringify = .{ .writer = &json_aw.writer, .options = .{} };
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
    try ws.endObject();

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
        try ws.endObject(); // summary

        // files (include root_path in each entry)
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

    const json_raw = json_aw.written();
    const json_safe = try std.mem.replaceOwned(u8, allocator, json_raw, "</script>", "<\\/script>");
    defer allocator.free(json_safe);

    var aw: std.io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    try aw.writer.writeAll(combined_dashboard_template[0..split_pos]);
    try aw.writer.writeAll(json_safe);
    try aw.writer.writeAll(combined_dashboard_template[split_pos + marker.len ..]);

    var html_file = try std.fs.cwd().createFile(html_path, .{ .truncate = true });
    defer html_file.close();
    try html_file.writeAll(aw.written());
}
