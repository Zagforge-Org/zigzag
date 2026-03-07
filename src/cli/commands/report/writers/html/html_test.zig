const std = @import("std");
const JobEntry = @import("../../../../../jobs/entry.zig").JobEntry;
const BinaryEntry = @import("../../../../../jobs/entry.zig").BinaryEntry;
const Config = @import("../../../config/config.zig").Config;
const ReportData = @import("../aggregator.zig").ReportData;

const writeHtmlReport = @import("./html.zig").writeHtmlReport;
const writeContentJson = @import("./html.zig").writeContentJson;
const writeCombinedContentJson = @import("./html.zig").writeCombinedContentJson;
const CombinedContentPath = @import("./html.zig").CombinedContentPath;

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

    var cfg = Config.default(alloc);
    defer cfg.deinit();

    var data = try ReportData.init(alloc, &file_entries, &binary_entries, null);
    defer data.deinit();

    try writeHtmlReport(&data, html_path, ".", &cfg, alloc);

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

    var cfg = Config.default(alloc);
    defer cfg.deinit();

    var data = try ReportData.init(alloc, &file_entries, &binary_entries, null);
    defer data.deinit();

    try writeHtmlReport(&data, html_path, "src", &cfg, alloc);

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

    var cfg = Config.default(alloc);
    defer cfg.deinit();

    var data = try ReportData.init(alloc, &file_entries, &binary_entries, null);
    defer data.deinit();

    try writeHtmlReport(&data, html_path, "src", &cfg, alloc);

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

    var cfg = Config.default(alloc);
    defer cfg.deinit();

    var data = try ReportData.init(alloc, &file_entries, &binary_entries, null);
    defer data.deinit();

    try writeHtmlReport(&data, html_path, "assets", &cfg, alloc);

    const content = try tmp.dir.readFileAlloc(alloc, "report.html", 4 << 20);
    defer alloc.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "assets/logo.png") != null);
}

test "writeHtmlReport sanitizes </script> in content" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);
    const html_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.html" });
    defer alloc.free(html_path);

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();
    try file_entries.put("evil.js", JobEntry{
        .path = "evil.js",
        .content = @constCast("var x = '</script><script>alert(1)</script>';"),
        .size = 44,
        .mtime = 0,
        .extension = ".js",
        .line_count = 1,
    });

    var binary_entries = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries.deinit();

    var cfg = Config.default(alloc);
    defer cfg.deinit();

    var data = try ReportData.init(alloc, &file_entries, &binary_entries, null);
    defer data.deinit();

    try writeHtmlReport(&data, html_path, ".", &cfg, alloc);

    const content = try tmp.dir.readFileAlloc(alloc, "report.html", 4 << 20);
    defer alloc.free(content);

    // The raw </script> from file content must be escaped as <\/script>
    try std.testing.expect(std.mem.indexOf(u8, content, "<\\/script>") != null);
}

test "writeContentJson produces valid JSON object with single entry" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const out_path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(out_path);
    const content_path = try std.fs.path.join(alloc, &.{ out_path, "content.json" });
    defer alloc.free(content_path);

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();

    const content1: []u8 = try alloc.dupe(u8, "hello world");
    defer alloc.free(content1);
    try file_entries.put("src/main.zig", .{
        .path = "src/main.zig", .content = content1,
        .size = 11, .mtime = 0, .extension = ".zig", .line_count = 1,
    });

    try writeContentJson(&file_entries, content_path, alloc);

    const written = try std.fs.cwd().readFileAlloc(alloc, content_path, 1024 * 1024);
    defer alloc.free(written);

    try std.testing.expect(std.mem.indexOf(u8, written, "src/main.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "hello world") != null);
    try std.testing.expectEqual(written[0], '{');
    try std.testing.expectEqual(written[written.len - 1], '}');
}

test "writeContentJson produces valid parseable JSON with multiple entries" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const out_path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(out_path);
    const content_path = try std.fs.path.join(alloc, &.{ out_path, "content.json" });
    defer alloc.free(content_path);

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();

    const c1: []u8 = try alloc.dupe(u8, "aaa");
    const c2: []u8 = try alloc.dupe(u8, "bbb");
    defer alloc.free(c1);
    defer alloc.free(c2);
    try file_entries.put("a.zig", .{ .path = "a.zig", .content = c1, .size = 3, .mtime = 0, .extension = ".zig", .line_count = 1 });
    try file_entries.put("b.zig", .{ .path = "b.zig", .content = c2, .size = 3, .mtime = 0, .extension = ".zig", .line_count = 1 });

    try writeContentJson(&file_entries, content_path, alloc);

    const written = try std.fs.cwd().readFileAlloc(alloc, content_path, 1024 * 1024);
    defer alloc.free(written);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, written, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(std.json.Value.object, std.meta.activeTag(parsed.value));
    try std.testing.expectEqual(@as(usize, 2), parsed.value.object.count());
}

test "writeContentJson escapes special characters in content" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const out_path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(out_path);
    const content_path = try std.fs.path.join(alloc, &.{ out_path, "content.json" });
    defer alloc.free(content_path);

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();

    // Content with characters that need JSON escaping
    const special_content: []u8 = try alloc.dupe(u8, "line1\nline2\t\"quoted\"\\backslash");
    defer alloc.free(special_content);
    try file_entries.put("test.txt", .{ .path = "test.txt", .content = special_content, .size = 30, .mtime = 0, .extension = ".txt", .line_count = 2 });

    try writeContentJson(&file_entries, content_path, alloc);

    const written = try std.fs.cwd().readFileAlloc(alloc, content_path, 1024 * 1024);
    defer alloc.free(written);

    // Must parse as valid JSON
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, written, .{});
    defer parsed.deinit();
    const val = parsed.value.object.get("test.txt") orelse return error.MissingKey;
    try std.testing.expectEqualStrings("line1\nline2\t\"quoted\"\\backslash", val.string);
}

test "writeContentJson produces empty object for empty map" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const out_path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(out_path);
    const content_path = try std.fs.path.join(alloc, &.{ out_path, "content.json" });
    defer alloc.free(content_path);

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();

    try writeContentJson(&file_entries, content_path, alloc);

    const written = try std.fs.cwd().readFileAlloc(alloc, content_path, 1024 * 1024);
    defer alloc.free(written);
    try std.testing.expectEqualStrings("{}", written);
}

test "writeCombinedContentJson uses root_path:path as key to avoid collisions" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const out_path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(out_path);
    const content_path = try std.fs.path.join(alloc, &.{ out_path, "combined-content.json" });
    defer alloc.free(content_path);

    // Two paths each with a file at "src/main.zig"
    var entries_a = std.StringHashMap(JobEntry).init(alloc);
    defer entries_a.deinit();
    const ca: []u8 = try alloc.dupe(u8, "backend content");
    defer alloc.free(ca);
    try entries_a.put("src/main.zig", .{ .path = "src/main.zig", .content = ca, .size = 15, .mtime = 0, .extension = ".zig", .line_count = 1 });

    var entries_b = std.StringHashMap(JobEntry).init(alloc);
    defer entries_b.deinit();
    const cb: []u8 = try alloc.dupe(u8, "frontend content");
    defer alloc.free(cb);
    try entries_b.put("src/main.zig", .{ .path = "src/main.zig", .content = cb, .size = 16, .mtime = 0, .extension = ".zig", .line_count = 1 });

    const paths = [_]CombinedContentPath{
        .{ .root_path = "./backend", .file_entries = &entries_a },
        .{ .root_path = "./frontend", .file_entries = &entries_b },
    };
    try writeCombinedContentJson(&paths, content_path, alloc);

    const written = try std.fs.cwd().readFileAlloc(alloc, content_path, 1024 * 1024);
    defer alloc.free(written);

    // Both keys must be present — no collision
    try std.testing.expect(std.mem.indexOf(u8, written, "./backend:src/main.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "./frontend:src/main.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "backend content") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "frontend content") != null);
}

test "writeCombinedContentJson produces valid JSON with two paths" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const out_path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(out_path);
    const content_path = try std.fs.path.join(alloc, &.{ out_path, "combined-content.json" });
    defer alloc.free(content_path);

    var entries_a = std.StringHashMap(JobEntry).init(alloc);
    defer entries_a.deinit();
    const ca: []u8 = try alloc.dupe(u8, "hello");
    defer alloc.free(ca);
    try entries_a.put("a.zig", .{ .path = "a.zig", .content = ca, .size = 5, .mtime = 0, .extension = ".zig", .line_count = 1 });

    var entries_b = std.StringHashMap(JobEntry).init(alloc);
    defer entries_b.deinit();
    const cb: []u8 = try alloc.dupe(u8, "world");
    defer alloc.free(cb);
    try entries_b.put("b.zig", .{ .path = "b.zig", .content = cb, .size = 5, .mtime = 0, .extension = ".zig", .line_count = 1 });

    const paths = [_]CombinedContentPath{
        .{ .root_path = "./src", .file_entries = &entries_a },
        .{ .root_path = "./lib", .file_entries = &entries_b },
    };
    try writeCombinedContentJson(&paths, content_path, alloc);

    const written = try std.fs.cwd().readFileAlloc(alloc, content_path, 1024 * 1024);
    defer alloc.free(written);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, written, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(std.json.Value.object, std.meta.activeTag(parsed.value));
    try std.testing.expectEqual(@as(usize, 2), parsed.value.object.count());
}
