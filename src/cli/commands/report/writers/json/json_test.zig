const std = @import("std");
const Config = @import("../../../config/config.zig").Config;
const JobEntry = @import("../../../../../jobs/entry.zig").JobEntry;
const BinaryEntry = @import("../../../../../jobs/entry.zig").BinaryEntry;
const ReportData = @import("../aggregator.zig").ReportData;
const writeJsonReport = @import("./json.zig").writeJsonReport;

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
