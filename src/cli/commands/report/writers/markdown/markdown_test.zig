const std = @import("std");
const Config = @import("../../../config/config.zig").Config;
const JobEntry = @import("../../../../../jobs/entry.zig").JobEntry;
const BinaryEntry = @import("../../../../../jobs/entry.zig").BinaryEntry;
const ReportData = @import("../aggregator.zig").ReportData;
const writeReport = @import("./markdown.zig").writeReport;

test "writeReport creates file with header, TOC and file entries" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    const md_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.md" });
    defer alloc.free(md_path);

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();
    var binary_entries = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries.deinit();

    try file_entries.put("src/b_util.zig", JobEntry{
        .path = "src/b_util.zig",
        .content = @constCast("pub fn helper() void {}"),
        .size = 22,
        .mtime = 1700000000000000000,
        .extension = ".zig",
        .line_count = 1,
    });
    try file_entries.put("src/a_main.zig", JobEntry{
        .path = "src/a_main.zig",
        .content = @constCast("const std = @import(\"std\");"),
        .size = 26,
        .mtime = 1700000000000000000,
        .extension = ".zig",
        .line_count = 1,
    });

    var cfg = Config.default(alloc);
    defer cfg.deinit();

    var data = try ReportData.init(alloc, &file_entries, &binary_entries, null);
    defer data.deinit();

    try writeReport(&data, &file_entries, md_path, "src", &cfg, alloc);

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

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();
    var binary_entries = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries.deinit();

    var cfg = Config.default(alloc);
    defer cfg.deinit();

    var data = try ReportData.init(alloc, &file_entries, &binary_entries, null);
    defer data.deinit();

    try writeReport(&data, &file_entries, md_path, "empty_dir", &cfg, alloc);

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

    var cfg = Config.default(alloc);
    defer cfg.deinit();

    var file_entries1 = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries1.deinit();
    var binary_entries1 = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries1.deinit();
    try file_entries1.put("first.zig", JobEntry{ .path = "first.zig", .content = @constCast("// first"), .size = 7, .mtime = 0, .extension = ".zig", .line_count = 1 });
    var data1 = try ReportData.init(alloc, &file_entries1, &binary_entries1, null);
    defer data1.deinit();
    try writeReport(&data1, &file_entries1, md_path, ".", &cfg, alloc);

    var file_entries2 = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries2.deinit();
    var binary_entries2 = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries2.deinit();
    try file_entries2.put("second.zig", JobEntry{ .path = "second.zig", .content = @constCast("// second"), .size = 8, .mtime = 0, .extension = ".zig", .line_count = 1 });
    var data2 = try ReportData.init(alloc, &file_entries2, &binary_entries2, null);
    defer data2.deinit();
    try writeReport(&data2, &file_entries2, md_path, ".", &cfg, alloc);

    const content = try tmp.dir.readFileAlloc(alloc, "report.md", 1 << 20);
    defer alloc.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "second.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "first.zig") == null);
}
