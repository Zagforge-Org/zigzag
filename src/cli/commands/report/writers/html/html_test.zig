const std = @import("std");
const JobEntry = @import("../../../../../jobs/entry.zig").JobEntry;
const BinaryEntry = @import("../../../../../jobs/entry.zig").BinaryEntry;
const Config = @import("../../../config/config.zig").Config;
const ReportData = @import("../aggregator.zig").ReportData;

const writeHtmlReport = @import("./html.zig").writeHtmlReport;

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
