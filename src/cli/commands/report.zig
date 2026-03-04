const std = @import("std");
const Config = @import("config.zig").Config;
const JobEntry = @import("../../jobs/entry.zig").JobEntry;
const BinaryEntry = @import("../../jobs/entry.zig").BinaryEntry;

/// Compute the output directory segment for a scanned path.
/// Relative paths have "./" stripped; absolute paths use basename only.
pub fn computeOutputSegment(path: []const u8) []const u8 {
    if (std.fs.path.isAbsolute(path)) {
        return std.fs.path.basename(path);
    }
    if (std.mem.startsWith(u8, path, "./")) {
        const stripped = path[2..];
        return if (stripped.len > 0) stripped else ".";
    }
    return if (path.len > 0) path else ".";
}

/// Resolve the full output file path for a given scanned path and filename.
/// Creates output directory tree if it doesn't exist.
/// Caller must free the returned slice.
pub fn resolveOutputPath(
    allocator: std.mem.Allocator,
    cfg: *const Config,
    scanned_path: []const u8,
    filename: []const u8,
) ![]u8 {
    const base_dir: []const u8 = if (cfg.output_dir) |d| d else "zigzag-reports";
    const segment = computeOutputSegment(scanned_path);
    const output_dir = try std.fs.path.join(allocator, &.{ base_dir, segment });
    defer allocator.free(output_dir);
    try std.fs.cwd().makePath(output_dir);
    return std.fs.path.join(allocator, &.{ output_dir, filename });
}

/// Write a single file entry to the report with metadata
fn writeFileEntry(
    md_file: *std.fs.File,
    entry: *const JobEntry,
    allocator: std.mem.Allocator,
    timezone_offset: ?i64,
) !void {
    const size_str = try entry.formatSize(allocator);
    defer allocator.free(size_str);

    const mtime_str = try entry.formatMtime(allocator, timezone_offset);
    defer allocator.free(mtime_str);

    const lang = entry.getLanguage();

    const header = try std.fmt.allocPrint(
        allocator,
        "## File: `{s}`\n\n" ++
            "**Metadata:**\n" ++
            "- **Size:** {s}\n" ++
            "- **Language:** {s}\n" ++
            "- **Last Modified:** {s}\n\n",
        .{
            entry.path,
            size_str,
            if (lang.len > 0) lang else "unknown",
            mtime_str,
        },
    );
    defer allocator.free(header);
    try md_file.writeAll(header);

    const code_fence_start = if (lang.len > 0)
        try std.fmt.allocPrint(allocator, "```{s}\n", .{lang})
    else
        try allocator.dupe(u8, "```\n");
    defer allocator.free(code_fence_start);

    try md_file.writeAll(code_fence_start);
    try md_file.writeAll(entry.content);

    if (entry.content.len > 0 and entry.content[entry.content.len - 1] != '\n') {
        try md_file.writeAll("\n");
    }

    try md_file.writeAll("```\n\n");
}

/// Serialize the in-memory entries map to report.md.
/// Called both from one-shot mode and watch mode.
pub fn writeReport(
    file_entries: *const std.StringHashMap(JobEntry),
    md_path: []const u8,
    root_path: []const u8,
    cfg: *const Config,
    allocator: std.mem.Allocator,
) !void {
    const output_filename = std.fs.path.basename(md_path);
    std.log.info("Building {s} for {s}...", .{ output_filename, root_path });

    var md_file = try std.fs.cwd().createFile(md_path, .{ .truncate = true });
    defer md_file.close();

    // Header with current timestamp
    const now = std.time.timestamp();
    const local_now = if (cfg.timezone_offset) |offset| now + offset else now;
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(local_now) };
    const day_seconds = epoch_seconds.getDaySeconds();
    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    const header = try std.fmt.allocPrint(
        allocator,
        "# Code Report for: `{s}`\n\n" ++
            "Generated on: {d}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}\n\n" ++
            "---\n\n",
        .{
            root_path,
            year_day.year,
            month_day.month.numeric(),
            month_day.day_index + 1,
            day_seconds.getHoursIntoDay(),
            day_seconds.getMinutesIntoHour(),
            day_seconds.getSecondsIntoMinute(),
        },
    );
    defer allocator.free(header);
    try md_file.writeAll(header);

    // Table of contents
    try md_file.writeAll("## Table of Contents\n\n");

    var toc_list: std.ArrayList([]const u8) = .empty;
    defer {
        for (toc_list.items) |item| allocator.free(item);
        toc_list.deinit(allocator);
    }

    var it = file_entries.iterator();
    while (it.next()) |entry| {
        const toc_entry = try std.fmt.allocPrint(allocator, "- [{s}](#{s})\n", .{
            entry.value_ptr.path,
            entry.value_ptr.path,
        });
        try toc_list.append(allocator, toc_entry);
    }

    std.mem.sort([]const u8, toc_list.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    for (toc_list.items) |toc_entry| try md_file.writeAll(toc_entry);
    try md_file.writeAll("\n---\n\n");

    // Sorted file entries
    var sorted_entries: std.ArrayList(JobEntry) = .empty;
    defer sorted_entries.deinit(allocator);

    it = file_entries.iterator();
    while (it.next()) |entry| try sorted_entries.append(allocator, entry.value_ptr.*);

    std.mem.sort(JobEntry, sorted_entries.items, {}, struct {
        fn lessThan(_: void, a: JobEntry, b: JobEntry) bool {
            return std.mem.lessThan(u8, a.path, b.path);
        }
    }.lessThan);

    for (sorted_entries.items) |*entry| {
        try writeFileEntry(&md_file, entry, allocator, cfg.timezone_offset);
    }
}

/// Derive a JSON output path from the markdown path by replacing the extension.
pub fn deriveJsonPath(allocator: std.mem.Allocator, md_path: []const u8) ![]u8 {
    if (std.mem.endsWith(u8, md_path, ".md")) {
        return std.fmt.allocPrint(allocator, "{s}.json", .{md_path[0 .. md_path.len - 3]});
    }
    return std.fmt.allocPrint(allocator, "{s}.json", .{md_path});
}

/// Language aggregate for the JSON summary section.
const LanguageStat = struct {
    name: []const u8,
    files: usize,
    lines: usize,
    size_bytes: u64,
};

/// Serialize analytics data to a JSON report file alongside the markdown report.
pub fn writeJsonReport(
    file_entries: *const std.StringHashMap(JobEntry),
    binary_entries: *const std.StringHashMap(BinaryEntry),
    json_path: []const u8,
    root_path: []const u8,
    cfg: *const Config,
    allocator: std.mem.Allocator,
) !void {
    const output_filename = std.fs.path.basename(json_path);
    std.log.info("Building {s} for {s}...", .{ output_filename, root_path });

    var aw: std.io.Writer.Allocating = .init(allocator);
    defer aw.deinit();

    // Aggregate per-language stats
    var lang_map = std.StringHashMap(LanguageStat).init(allocator);
    defer {
        var it = lang_map.iterator();
        while (it.next()) |entry| allocator.free(entry.value_ptr.name);
        lang_map.deinit();
    }

    var total_lines: usize = 0;
    var total_size: u64 = 0;

    var fit = file_entries.iterator();
    while (fit.next()) |entry| {
        const e = entry.value_ptr;
        total_lines += e.line_count;
        total_size += e.size;

        const lang = e.getLanguage();
        const lang_name = if (lang.len > 0) lang else "unknown";

        const gop = try lang_map.getOrPut(lang_name);
        if (!gop.found_existing) {
            gop.value_ptr.* = .{
                .name = try allocator.dupe(u8, lang_name),
                .files = 0,
                .lines = 0,
                .size_bytes = 0,
            };
        }
        gop.value_ptr.files += 1;
        gop.value_ptr.lines += e.line_count;
        gop.value_ptr.size_bytes += e.size;
    }

    // Sort language stats by name for deterministic output
    var lang_list: std.ArrayList(LanguageStat) = .empty;
    defer lang_list.deinit(allocator);
    var lit = lang_map.iterator();
    while (lit.next()) |entry| try lang_list.append(allocator, entry.value_ptr.*);
    std.mem.sort(LanguageStat, lang_list.items, {}, struct {
        fn lessThan(_: void, a: LanguageStat, b: LanguageStat) bool {
            return std.mem.lessThan(u8, a.name, b.name);
        }
    }.lessThan);

    // Sort file entries by path
    var sorted_files: std.ArrayList(JobEntry) = .empty;
    defer sorted_files.deinit(allocator);
    fit = file_entries.iterator();
    while (fit.next()) |entry| try sorted_files.append(allocator, entry.value_ptr.*);
    std.mem.sort(JobEntry, sorted_files.items, {}, struct {
        fn lessThan(_: void, a: JobEntry, b: JobEntry) bool {
            return std.mem.lessThan(u8, a.path, b.path);
        }
    }.lessThan);

    // Sort binary entries by path
    var sorted_binaries: std.ArrayList(BinaryEntry) = .empty;
    defer sorted_binaries.deinit(allocator);
    var bit = binary_entries.iterator();
    while (bit.next()) |entry| try sorted_binaries.append(allocator, entry.value_ptr.*);
    std.mem.sort(BinaryEntry, sorted_binaries.items, {}, struct {
        fn lessThan(_: void, a: BinaryEntry, b: BinaryEntry) bool {
            return std.mem.lessThan(u8, a.path, b.path);
        }
    }.lessThan);

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
    try ws.write(file_entries.count());
    try ws.objectField("binary_files");
    try ws.write(binary_entries.count());
    try ws.objectField("total_lines");
    try ws.write(total_lines);
    try ws.objectField("total_size_bytes");
    try ws.write(total_size);
    try ws.objectField("languages");
    try ws.beginArray();
    for (lang_list.items) |ls| {
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
    for (sorted_files.items) |e| {
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
    for (sorted_binaries.items) |b| {
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

/// Derive an HTML output path from the markdown path by replacing the extension.
pub fn deriveHtmlPath(allocator: std.mem.Allocator, md_path: []const u8) ![]u8 {
    if (std.mem.endsWith(u8, md_path, ".md")) {
        return std.fmt.allocPrint(allocator, "{s}.html", .{md_path[0 .. md_path.len - 3]});
    }
    return std.fmt.allocPrint(allocator, "{s}.html", .{md_path});
}

const dashboard_template = @embedFile("../../templates/dashboard.html");

/// Write a self-contained HTML dashboard alongside the markdown report.
/// The template is loaded from src/templates/dashboard.html via @embedFile.
pub fn writeHtmlReport(
    file_entries: *const std.StringHashMap(JobEntry),
    binary_entries: *const std.StringHashMap(BinaryEntry),
    html_path: []const u8,
    root_path: []const u8,
    cfg: *const Config,
    allocator: std.mem.Allocator,
) !void {
    const output_filename = std.fs.path.basename(html_path);
    std.log.info("Building {s} for {s}...", .{ output_filename, root_path });

    // --- Aggregate stats (same logic as writeJsonReport) ---
    var lang_map = std.StringHashMap(LanguageStat).init(allocator);
    defer {
        var it = lang_map.iterator();
        while (it.next()) |entry| allocator.free(entry.value_ptr.name);
        lang_map.deinit();
    }

    var total_lines: usize = 0;
    var total_size: u64 = 0;

    var fit = file_entries.iterator();
    while (fit.next()) |entry| {
        const e = entry.value_ptr;
        total_lines += e.line_count;
        total_size += e.size;

        const lang = e.getLanguage();
        const lang_name = if (lang.len > 0) lang else "unknown";
        const gop = try lang_map.getOrPut(lang_name);
        if (!gop.found_existing) {
            gop.value_ptr.* = .{
                .name = try allocator.dupe(u8, lang_name),
                .files = 0,
                .lines = 0,
                .size_bytes = 0,
            };
        }
        gop.value_ptr.files += 1;
        gop.value_ptr.lines += e.line_count;
        gop.value_ptr.size_bytes += e.size;
    }

    var lang_list: std.ArrayList(LanguageStat) = .empty;
    defer lang_list.deinit(allocator);
    var lit = lang_map.iterator();
    while (lit.next()) |entry| try lang_list.append(allocator, entry.value_ptr.*);
    std.mem.sort(LanguageStat, lang_list.items, {}, struct {
        fn lessThan(_: void, a: LanguageStat, b: LanguageStat) bool {
            return std.mem.lessThan(u8, a.name, b.name);
        }
    }.lessThan);

    var sorted_files: std.ArrayList(JobEntry) = .empty;
    defer sorted_files.deinit(allocator);
    fit = file_entries.iterator();
    while (fit.next()) |entry| try sorted_files.append(allocator, entry.value_ptr.*);
    std.mem.sort(JobEntry, sorted_files.items, {}, struct {
        fn lessThan(_: void, a: JobEntry, b: JobEntry) bool {
            return std.mem.lessThan(u8, a.path, b.path);
        }
    }.lessThan);

    var sorted_binaries: std.ArrayList(BinaryEntry) = .empty;
    defer sorted_binaries.deinit(allocator);
    var bit = binary_entries.iterator();
    while (bit.next()) |entry| try sorted_binaries.append(allocator, entry.value_ptr.*);
    std.mem.sort(BinaryEntry, sorted_binaries.items, {}, struct {
        fn lessThan(_: void, a: BinaryEntry, b: BinaryEntry) bool {
            return std.mem.lessThan(u8, a.path, b.path);
        }
    }.lessThan);

    // --- Build current timestamp ---
    const now = std.time.timestamp();
    const local_now = if (cfg.timezone_offset) |offset| now + offset else now;
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(local_now) };
    const day_seconds = epoch_seconds.getDaySeconds();
    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    const generated_at_str = try std.fmt.allocPrint(
        allocator,
        "{d}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}",
        .{
            year_day.year,
            month_day.month.numeric(),
            month_day.day_index + 1,
            day_seconds.getHoursIntoDay(),
            day_seconds.getMinutesIntoHour(),
            day_seconds.getSecondsIntoMinute(),
        },
    );
    defer allocator.free(generated_at_str);

    // --- Split template on two markers ---
    // __ZIGZAG_DATA__    → small report JSON (no file content) parsed eagerly
    // __ZIGZAG_CONTENT__ → content map {"path": "source"} loaded lazily on first viewer open
    const marker = "__ZIGZAG_DATA__";
    const content_marker = "__ZIGZAG_CONTENT__";
    const split_pos = std.mem.indexOf(u8, dashboard_template, marker) orelse
        return error.MissingTemplateMarker;
    const content_split_pos = std.mem.indexOf(u8, dashboard_template, content_marker) orelse
        return error.MissingTemplateMarker;

    // Build the report JSON (without file content) ----------------------------
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
    try ws.write(generated_at_str);
    try ws.objectField("version");
    try ws.write(cfg.version);
    try ws.objectField("watch_mode");
    try ws.write(cfg.watch);
    try ws.endObject();

    // summary
    try ws.objectField("summary");
    try ws.beginObject();
    try ws.objectField("source_files");
    try ws.write(file_entries.count());
    try ws.objectField("binary_files");
    try ws.write(binary_entries.count());
    try ws.objectField("total_lines");
    try ws.write(total_lines);
    try ws.objectField("total_size_bytes");
    try ws.write(total_size);
    try ws.objectField("languages");
    try ws.beginArray();
    for (lang_list.items) |ls| {
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

    // files — metadata only, no content (content goes in the separate fc block)
    try ws.objectField("files");
    try ws.beginArray();
    for (sorted_files.items) |e| {
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
    for (sorted_binaries.items) |b| {
        try ws.beginObject();
        try ws.objectField("path");
        try ws.write(b.path);
        try ws.objectField("size");
        try ws.write(b.size);
        try ws.endObject();
    }
    try ws.endArray();

    try ws.endObject();

    // Build the content map {"path": "source", ...} ---------------------------
    var content_aw: std.io.Writer.Allocating = .init(allocator);
    defer content_aw.deinit();

    var cws: std.json.Stringify = .{ .writer = &content_aw.writer, .options = .{} };
    try cws.beginObject();
    for (sorted_files.items) |e| {
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
}

// ============================================================
// Tests
// ============================================================

test "deriveJsonPath replaces .md extension with .json" {
    const alloc = std.testing.allocator;
    const result = try deriveJsonPath(alloc, "report.md");
    defer alloc.free(result);
    try std.testing.expectEqualStrings("report.json", result);
}

test "deriveJsonPath handles full path with .md extension" {
    const alloc = std.testing.allocator;
    const result = try deriveJsonPath(alloc, "/some/dir/output.md");
    defer alloc.free(result);
    try std.testing.expectEqualStrings("/some/dir/output.json", result);
}

test "deriveJsonPath appends .json when no .md extension" {
    const alloc = std.testing.allocator;
    const result = try deriveJsonPath(alloc, "output.txt");
    defer alloc.free(result);
    try std.testing.expectEqualStrings("output.txt.json", result);
}

test "deriveHtmlPath replaces .md extension with .html" {
    const alloc = std.testing.allocator;
    const result = try deriveHtmlPath(alloc, "report.md");
    defer alloc.free(result);
    try std.testing.expectEqualStrings("report.html", result);
}

test "deriveHtmlPath handles full path with .md extension" {
    const alloc = std.testing.allocator;
    const result = try deriveHtmlPath(alloc, "/some/dir/output.md");
    defer alloc.free(result);
    try std.testing.expectEqualStrings("/some/dir/output.html", result);
}

test "deriveHtmlPath appends .html when no .md extension" {
    const alloc = std.testing.allocator;
    const result = try deriveHtmlPath(alloc, "output.txt");
    defer alloc.free(result);
    try std.testing.expectEqualStrings("output.txt.html", result);
}

test "writeHtmlReport creates file with expected HTML structure" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);
    const html_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.html" });
    defer alloc.free(html_path);

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();
    var binary_entries = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries.deinit();

    var cfg = Config.initDefault(alloc);
    defer cfg.deinit();

    try writeHtmlReport(&file_entries, &binary_entries, html_path, ".", &cfg, alloc);

    const content = try tmp.dir.readFileAlloc(alloc, "report.html", 4 << 20);
    defer alloc.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "<!doctype html>") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "<title>") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "window.REPORT =") != null);
}

test "writeHtmlReport includes summary stats in embedded JSON" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);
    const html_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.html" });
    defer alloc.free(html_path);

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();
    try file_entries.put("src/main.zig", JobEntry{
        .path = "src/main.zig",
        .content = @constCast("const x = 1;\n"),
        .size = 500,
        .mtime = 0,
        .extension = ".zig",
        .line_count = 1,
    });

    var binary_entries = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries.deinit();

    var cfg = Config.initDefault(alloc);
    defer cfg.deinit();

    try writeHtmlReport(&file_entries, &binary_entries, html_path, "src", &cfg, alloc);

    const content = try tmp.dir.readFileAlloc(alloc, "report.html", 4 << 20);
    defer alloc.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "\"source_files\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"total_lines\"") != null);
}

test "writeHtmlReport includes file entry path in embedded JSON" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);
    const html_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.html" });
    defer alloc.free(html_path);

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();
    try file_entries.put("src/utils.zig", JobEntry{
        .path = "src/utils.zig",
        .content = @constCast(""),
        .size = 100,
        .mtime = 0,
        .extension = ".zig",
        .line_count = 5,
    });

    var binary_entries = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries.deinit();

    var cfg = Config.initDefault(alloc);
    defer cfg.deinit();

    try writeHtmlReport(&file_entries, &binary_entries, html_path, "src", &cfg, alloc);

    const content = try tmp.dir.readFileAlloc(alloc, "report.html", 4 << 20);
    defer alloc.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "src/utils.zig") != null);
}

test "writeHtmlReport includes binary entry in embedded JSON" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);
    const html_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.html" });
    defer alloc.free(html_path);

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();

    var binary_entries = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries.deinit();
    try binary_entries.put("assets/logo.png", BinaryEntry{
        .path = "assets/logo.png",
        .size = 2048,
        .mtime = 0,
        .extension = ".png",
    });

    var cfg = Config.initDefault(alloc);
    defer cfg.deinit();

    try writeHtmlReport(&file_entries, &binary_entries, html_path, ".", &cfg, alloc);

    const content = try tmp.dir.readFileAlloc(alloc, "report.html", 4 << 20);
    defer alloc.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "assets/logo.png") != null);
}

test "writeHtmlReport includes language stats in embedded JSON" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);
    const html_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.html" });
    defer alloc.free(html_path);

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();
    try file_entries.put("main.zig", JobEntry{ .path = "main.zig", .content = @constCast(""), .size = 10, .mtime = 0, .extension = ".zig", .line_count = 5 });
    try file_entries.put("config.json", JobEntry{ .path = "config.json", .content = @constCast(""), .size = 50, .mtime = 0, .extension = ".json", .line_count = 3 });

    var binary_entries = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries.deinit();

    var cfg = Config.initDefault(alloc);
    defer cfg.deinit();

    try writeHtmlReport(&file_entries, &binary_entries, html_path, ".", &cfg, alloc);

    const content = try tmp.dir.readFileAlloc(alloc, "report.html", 4 << 20);
    defer alloc.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "\"languages\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"zig\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"json\"") != null);
}

test "writeHtmlReport includes meta fields in embedded JSON" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);
    const html_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.html" });
    defer alloc.free(html_path);

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();
    var binary_entries = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries.deinit();

    var cfg = Config.initDefault(alloc);
    defer cfg.deinit();

    try writeHtmlReport(&file_entries, &binary_entries, html_path, "myproject", &cfg, alloc);

    const content = try tmp.dir.readFileAlloc(alloc, "report.html", 4 << 20);
    defer alloc.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "\"meta\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"watch_mode\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"generated_at\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"version\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "myproject") != null);
}

test "writeHtmlReport includes file content in embedded JSON" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);
    const html_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.html" });
    defer alloc.free(html_path);

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();
    try file_entries.put("src/hello.zig", JobEntry{
        .path = "src/hello.zig",
        .content = @constCast("const greeting = \"hello world\";\n"),
        .size = 33,
        .mtime = 0,
        .extension = ".zig",
        .line_count = 1,
    });

    var binary_entries = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries.deinit();

    var cfg = Config.initDefault(alloc);
    defer cfg.deinit();

    try writeHtmlReport(&file_entries, &binary_entries, html_path, "src", &cfg, alloc);

    const content = try tmp.dir.readFileAlloc(alloc, "report.html", 4 << 20);
    defer alloc.free(content);

    // Content is now stored in the <script id="fc"> block (lazy content map),
    // not as a field in the main report JSON.
    try std.testing.expect(std.mem.indexOf(u8, content, "id=\"fc\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "hello world") != null);
}

test "writeJsonReport creates file with expected top-level JSON keys" {
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

    var cfg = Config.initDefault(alloc);
    defer cfg.deinit();

    try writeJsonReport(&file_entries, &binary_entries, json_path, ".", &cfg, alloc);

    const content = try tmp.dir.readFileAlloc(alloc, "report.json", 1 << 20);
    defer alloc.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "\"meta\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"summary\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"files\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"binaries\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"version\"") != null);
}

test "writeJsonReport includes file metadata and line counts" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    const json_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.json" });
    defer alloc.free(json_path);

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();
    try file_entries.put("src/main.zig", JobEntry{
        .path = "src/main.zig",
        .content = @constCast("const x = 1;\nconst y = 2;\n"),
        .size = 1234,
        .mtime = 1700000000000000000,
        .extension = ".zig",
        .line_count = 2,
    });

    var binary_entries = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries.deinit();

    var cfg = Config.initDefault(alloc);
    defer cfg.deinit();

    try writeJsonReport(&file_entries, &binary_entries, json_path, "src", &cfg, alloc);

    const content = try tmp.dir.readFileAlloc(alloc, "report.json", 1 << 20);
    defer alloc.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "src/main.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"language\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"zig\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"lines\"") != null);
}

test "writeJsonReport includes binary file entries" {
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
    try binary_entries.put("assets/logo.png", BinaryEntry{
        .path = "assets/logo.png",
        .size = 4096,
        .mtime = 1700000000000000000,
        .extension = ".png",
    });

    var cfg = Config.initDefault(alloc);
    defer cfg.deinit();

    try writeJsonReport(&file_entries, &binary_entries, json_path, ".", &cfg, alloc);

    const content = try tmp.dir.readFileAlloc(alloc, "report.json", 1 << 20);
    defer alloc.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "assets/logo.png") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "\".png\"") != null);
}

test "writeJsonReport aggregates summary statistics correctly" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    const json_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.json" });
    defer alloc.free(json_path);

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();
    try file_entries.put("a.zig", JobEntry{ .path = "a.zig", .content = @constCast(""), .size = 100, .mtime = 0, .extension = ".zig", .line_count = 10 });
    try file_entries.put("b.zig", JobEntry{ .path = "b.zig", .content = @constCast(""), .size = 200, .mtime = 0, .extension = ".zig", .line_count = 20 });

    var binary_entries = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries.deinit();
    try binary_entries.put("img.png", BinaryEntry{ .path = "img.png", .size = 0, .mtime = 0, .extension = ".png" });

    var cfg = Config.initDefault(alloc);
    defer cfg.deinit();

    try writeJsonReport(&file_entries, &binary_entries, json_path, ".", &cfg, alloc);

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

    var cfg = Config.initDefault(alloc);
    defer cfg.deinit();

    try writeJsonReport(&file_entries, &binary_entries, json_path, ".", &cfg, alloc);

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

    var cfg = Config.initDefault(alloc);
    defer cfg.deinit();

    try writeJsonReport(&file_entries, &binary_entries, json_path, ".", &cfg, alloc);

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

    var cfg = Config.initDefault(alloc);
    defer cfg.deinit();

    try writeJsonReport(&file_entries, &binary_entries, json_path, "my/project", &cfg, alloc);

    const content = try tmp.dir.readFileAlloc(alloc, "report.json", 1 << 20);
    defer alloc.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "my/project") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"generated_at_ns\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"scanned_paths\"") != null);
}

test "writeReport creates file with header, TOC and file entries" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    const md_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.md" });
    defer alloc.free(md_path);

    var entries = std.StringHashMap(JobEntry).init(alloc);
    defer entries.deinit();

    try entries.put("src/b_util.zig", JobEntry{
        .path = "src/b_util.zig",
        .content = @constCast("pub fn helper() void {}"),
        .size = 22,
        .mtime = 1700000000000000000,
        .extension = ".zig",
        .line_count = 1,
    });
    try entries.put("src/a_main.zig", JobEntry{
        .path = "src/a_main.zig",
        .content = @constCast("const std = @import(\"std\");"),
        .size = 26,
        .mtime = 1700000000000000000,
        .extension = ".zig",
        .line_count = 1,
    });

    var cfg = Config.initDefault(alloc);
    defer cfg.deinit();

    try writeReport(&entries, md_path, "src", &cfg, alloc);

    const content = try tmp.dir.readFileAlloc(alloc, "report.md", 1 << 20);
    defer alloc.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "# Code Report for: `src`") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "## Table of Contents") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "src/a_main.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "src/b_util.zig") != null);
    const pos_a = std.mem.indexOf(u8, content, "src/a_main.zig").?;
    const pos_b = std.mem.indexOf(u8, content, "src/b_util.zig").?;
    try std.testing.expect(pos_a < pos_b);
    try std.testing.expect(std.mem.indexOf(u8, content, "```zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const std = @import") != null);
}

test "writeReport handles empty entries map" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    const md_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.md" });
    defer alloc.free(md_path);

    var entries = std.StringHashMap(JobEntry).init(alloc);
    defer entries.deinit();

    var cfg = Config.initDefault(alloc);
    defer cfg.deinit();

    try writeReport(&entries, md_path, "empty_dir", &cfg, alloc);

    const content = try tmp.dir.readFileAlloc(alloc, "report.md", 1 << 20);
    defer alloc.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "# Code Report for: `empty_dir`") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "## Table of Contents") != null);
    try std.testing.expect(content.len > 0);
}

test "writeReport overwrites existing file" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    const md_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.md" });
    defer alloc.free(md_path);

    var cfg = Config.initDefault(alloc);
    defer cfg.deinit();

    var entries1 = std.StringHashMap(JobEntry).init(alloc);
    defer entries1.deinit();
    try entries1.put("first.zig", JobEntry{
        .path = "first.zig",
        .content = @constCast("// first"),
        .size = 7,
        .mtime = 0,
        .extension = ".zig",
        .line_count = 1,
    });
    try writeReport(&entries1, md_path, ".", &cfg, alloc);

    var entries2 = std.StringHashMap(JobEntry).init(alloc);
    defer entries2.deinit();
    try entries2.put("second.zig", JobEntry{
        .path = "second.zig",
        .content = @constCast("// second"),
        .size = 8,
        .mtime = 0,
        .extension = ".zig",
        .line_count = 1,
    });
    try writeReport(&entries2, md_path, ".", &cfg, alloc);

    const content = try tmp.dir.readFileAlloc(alloc, "report.md", 1 << 20);
    defer alloc.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "second.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "first.zig") == null);
}

test "computeOutputSegment strips leading ./" {
    try std.testing.expectEqualStrings("src", computeOutputSegment("./src"));
    try std.testing.expectEqualStrings("src/cli", computeOutputSegment("./src/cli"));
}

test "computeOutputSegment uses basename for absolute paths" {
    try std.testing.expectEqualStrings("src", computeOutputSegment("/home/user/project/src"));
}

test "computeOutputSegment returns path unchanged when no ./ prefix" {
    try std.testing.expectEqualStrings("src", computeOutputSegment("src"));
}

test "computeOutputSegment handles bare dot" {
    try std.testing.expectEqualStrings(".", computeOutputSegment("."));
    try std.testing.expectEqualStrings(".", computeOutputSegment("./"));
}

test "resolveOutputPath returns path under zigzag-reports by default" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_abs = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_abs);

    var cfg = @import("config.zig").Config.initDefault(allocator);
    defer cfg.deinit();
    // output_dir is null → default "zigzag-reports"
    // Use tmp_abs as base via output_dir to avoid writing to project CWD
    cfg.output_dir = try allocator.dupe(u8, tmp_abs);
    cfg._output_dir_allocated = true;

    const result = try resolveOutputPath(allocator, &cfg, "./src", "report.md");
    defer allocator.free(result);

    // The result should contain the tmp path, "src", and "report.md"
    try std.testing.expect(std.mem.indexOf(u8, result, "src") != null);
    try std.testing.expect(std.mem.endsWith(u8, result, "report.md"));
    // Verify the directory was actually created
    tmp.dir.access("src", .{}) catch |err| {
        std.debug.print("Expected 'src' dir to exist in tmp, got: {s}\n", .{@errorName(err)});
        return err;
    };
}
