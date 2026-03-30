const std = @import("std");
const Config = @import("../../../config/config.zig").Config;
const JobEntry = @import("../../../../../jobs/entry.zig").JobEntry;
const BinaryEntry = @import("../../../../../jobs/entry.zig").BinaryEntry;
const ReportData = @import("../aggregator.zig").ReportData;
const writeLlmReport = @import("./llm.zig").writeLlmReport;

test "writeLlmReport creates report with correct structure" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(tmp_path);

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    cfg.llm_max_lines = 150;

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();
    const src_content = "pub fn main() void {}\n";
    try file_entries.put("src/main.zig", .{
        .path = "src/main.zig",
        .content = @constCast(src_content),
        .size = src_content.len,
        .mtime = 0,
        .extension = ".zig",
        .line_count = 1,
    });

    var binary_entries = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries.deinit();

    const llm_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.llm.md" });
    defer alloc.free(llm_path);

    var data = try ReportData.init(alloc, &file_entries, &binary_entries, null);
    defer data.deinit();

    try writeLlmReport(&data, binary_entries.count(), llm_path, "src", &cfg, 0, alloc);

    const written = try std.fs.cwd().readFileAlloc(alloc, llm_path, 1024 * 1024);
    defer alloc.free(written);

    try std.testing.expect(std.mem.indexOf(u8, written, "# LLM Context: src") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "## Statistics") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "## File Index") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "## Source") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "src/main.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "pub fn main() void {}") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "- src/main.zig (1 lines, full)") != null);
}

test "writeLlmReport omits boilerplate files" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(tmp_path);

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    cfg.llm_max_lines = 150;

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();
    const lock_content = "{ \"dep\": \"1.0\" }\n";
    try file_entries.put("package-lock.json", .{
        .path = "package-lock.json",
        .content = @constCast(lock_content),
        .size = lock_content.len,
        .mtime = 0,
        .extension = ".json",
        .line_count = 1,
    });

    var binary_entries = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries.deinit();

    const llm_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.llm.md" });
    defer alloc.free(llm_path);

    var data = try ReportData.init(alloc, &file_entries, &binary_entries, null);
    defer data.deinit();

    try writeLlmReport(&data, binary_entries.count(), llm_path, "src", &cfg, 0, alloc);

    const written = try std.fs.cwd().readFileAlloc(alloc, llm_path, 1024 * 1024);
    defer alloc.free(written);

    try std.testing.expect(std.mem.indexOf(u8, written, "package-lock.json") == null);
    try std.testing.expect(std.mem.indexOf(u8, written, "Boilerplate skipped: 1") != null);
}

test "writeLlmReport includes llm_description when set" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(tmp_path);

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    cfg.llm_max_lines = 150;
    cfg.llm_description = try alloc.dupe(u8, "A great tool.");
    cfg._llm_description_allocated = true;

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();

    var binary_entries = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries.deinit();

    const llm_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.llm.md" });
    defer alloc.free(llm_path);

    var data = try ReportData.init(alloc, &file_entries, &binary_entries, null);
    defer data.deinit();

    try writeLlmReport(&data, binary_entries.count(), llm_path, "src", &cfg, 0, alloc);

    const written = try std.fs.cwd().readFileAlloc(alloc, llm_path, 1024 * 1024);
    defer alloc.free(written);

    try std.testing.expect(std.mem.indexOf(u8, written, "## Project Description") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "A great tool.") != null);
}

test "writeLlmReport emits AST chunks for Python files" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(tmp_path);

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    cfg.llm_max_lines = 150;

    const py_content =
        \\def greet():
        \\    pass
        \\
        \\def farewell():
        \\    pass
        \\
    ;

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();
    try file_entries.put("src/hello.py", .{
        .path = "src/hello.py",
        .content = @constCast(py_content),
        .size = py_content.len,
        .mtime = 0,
        .extension = ".py",
        .line_count = 6,
    });

    var binary_entries = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries.deinit();

    const llm_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.llm.md" });
    defer alloc.free(llm_path);

    var data = try ReportData.init(alloc, &file_entries, &binary_entries, null);
    defer data.deinit();

    try writeLlmReport(&data, 0, llm_path, "src", &cfg, 0, alloc);

    const written = try std.fs.cwd().readFileAlloc(alloc, llm_path, 1024 * 1024);
    defer alloc.free(written);

    // AST chunks appear in output
    try std.testing.expect(std.mem.indexOf(u8, written, "src/hello.py [1–2]") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "src/hello.py [4–5]") != null);
    // File index shows AST chunks count
    try std.testing.expect(std.mem.indexOf(u8, written, "2 AST chunks") != null);
    // No condensed marker
    try std.testing.expect(std.mem.indexOf(u8, written, "lines omitted]") == null);
}
