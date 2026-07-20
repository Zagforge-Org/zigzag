const std = @import("std");
const State = @import("State.zig");
const JobEntry = @import("../../../jobs/entries.zig").JobEntry;
const BinaryEntry = @import("../../../jobs/entries.zig").BinaryEntry;
const Config = @import("../config/Config.zig");
const writeAllReports = @import("reporter.zig").writeAllReports;

fn makeState(
    alloc: std.mem.Allocator,
    md_path: []const u8,
) State {
    var state: State = undefined;
    state.io = std.testing.io;
    state.root_path = "src";
    state.md_path = md_path;
    state.file_entries = std.StringHashMap(JobEntry).init(alloc);
    state.binary_entries = std.StringHashMap(BinaryEntry).init(alloc);
    state.entries_mutex = .init;
    state.allocator = alloc;
    state.file_ctx = .{ .io = std.testing.io, .ignore_list = .empty, .md = undefined, .md_mutex = undefined };
    state.llm_memo = .init(alloc);
    state.defer_frees = false;
    state.graveyard_files = .empty;
    state.graveyard_binaries = .empty;
    return state;
}

test "writeAllReports creates markdown file" {
    const alloc = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = path_buf[0..try tmp.dir.realPathFile(std.testing.io, ".", &path_buf)];
    const md_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.md" });
    defer alloc.free(md_path);

    var state = makeState(alloc, md_path);
    defer state.file_entries.deinit();
    defer state.binary_entries.deinit();
    defer state.file_ctx.ignore_list.deinit(alloc);
    defer state.llm_memo.deinit();
    defer state.graveyard_files.deinit(alloc);
    defer state.graveyard_binaries.deinit(alloc);

    var cfg = Config.default(alloc);
    defer cfg.deinit();

    writeAllReports(std.testing.io, &state, &cfg, null, &.{}, alloc, null);

    tmp.dir.access(std.testing.io, "report.md", .{}) catch |err| {
        std.debug.print("Expected report.md to exist, got: {s}\n", .{@errorName(err)});
        return err;
    };
}

test "writeAllReports creates JSON file when json_output is true" {
    const alloc = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = path_buf[0..try tmp.dir.realPathFile(std.testing.io, ".", &path_buf)];
    const md_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.md" });
    defer alloc.free(md_path);

    var state = makeState(alloc, md_path);
    defer state.file_entries.deinit();
    defer state.binary_entries.deinit();
    defer state.file_ctx.ignore_list.deinit(alloc);
    defer state.llm_memo.deinit();
    defer state.graveyard_files.deinit(alloc);
    defer state.graveyard_binaries.deinit(alloc);

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    cfg.json_output = true;

    writeAllReports(std.testing.io, &state, &cfg, null, &.{}, alloc, null);

    tmp.dir.access(std.testing.io, "report.json", .{}) catch |err| {
        std.debug.print("Expected report.json to exist, got: {s}\n", .{@errorName(err)});
        return err;
    };
}

test "writeAllReports creates HTML file when html_output is true" {
    const alloc = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = path_buf[0..try tmp.dir.realPathFile(std.testing.io, ".", &path_buf)];
    const md_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.md" });
    defer alloc.free(md_path);

    var state = makeState(alloc, md_path);
    defer state.file_entries.deinit();
    defer state.binary_entries.deinit();
    defer state.file_ctx.ignore_list.deinit(alloc);
    defer state.llm_memo.deinit();
    defer state.graveyard_files.deinit(alloc);
    defer state.graveyard_binaries.deinit(alloc);

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    cfg.html_output = true;

    writeAllReports(std.testing.io, &state, &cfg, null, &.{}, alloc, null);

    tmp.dir.access(std.testing.io, "report.html", .{}) catch |err| {
        std.debug.print("Expected report.html to exist, got: {s}\n", .{@errorName(err)});
        return err;
    };
}

test "writeAllReports with file entry produces non-empty markdown" {
    const alloc = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = path_buf[0..try tmp.dir.realPathFile(std.testing.io, ".", &path_buf)];
    const md_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.md" });
    defer alloc.free(md_path);

    var state = makeState(alloc, md_path);
    defer state.file_entries.deinit();
    defer state.binary_entries.deinit();
    defer state.file_ctx.ignore_list.deinit(alloc);
    defer state.llm_memo.deinit();
    defer state.graveyard_files.deinit(alloc);
    defer state.graveyard_binaries.deinit(alloc);

    try state.file_entries.put("src/main.zig", JobEntry{
        .path = "src/main.zig",
        .content = @constCast("pub fn main() void {}\n"),
        .size = 22,
        .mtime = 0,
        .extension = ".zig",
        .line_count = 1,
    });

    var cfg = Config.default(alloc);
    defer cfg.deinit();

    writeAllReports(std.testing.io, &state, &cfg, null, &.{}, alloc, null);

    const content = try tmp.dir.readFileAlloc(std.testing.io, "report.md", alloc, .limited(1 << 20));
    defer alloc.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "src/main.zig") != null);
}

test "writeAllReports repeated flushes leak nothing with all outputs enabled" {
    const alloc = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = path_buf[0..try tmp.dir.realPathFile(std.testing.io, ".", &path_buf)];
    const md_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.md" });
    defer alloc.free(md_path);

    var state = makeState(alloc, md_path);
    defer state.file_entries.deinit();
    defer state.binary_entries.deinit();
    defer state.file_ctx.ignore_list.deinit(alloc);
    defer state.llm_memo.deinit();
    defer state.graveyard_files.deinit(alloc);
    defer state.graveyard_binaries.deinit(alloc);

    try state.file_entries.put("src/main.py", JobEntry{
        .path = "src/main.py",
        .content = @constCast("def a():\n    pass\n\ndef b():\n    pass\n"),
        .size = 38,
        .mtime = 0,
        .extension = ".py",
        .line_count = 5,
    });
    try state.file_entries.put("src/util.zig", JobEntry{
        .path = "src/util.zig",
        .content = @constCast("pub fn util() void {}\n// comment\n"),
        .size = 33,
        .mtime = 0,
        .extension = ".zig",
        .line_count = 2,
    });

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    cfg.watch = true;
    cfg.json_output = true;
    cfg.html_output = true;
    cfg.llm_report = true;
    cfg.llm_chunk_size = 64; // force the chunked writer + manifest path

    // The watch debounce flush calls this repeatedly; the testing allocator
    // reports anything a flush fails to free.
    for (0..3) |_| {
        writeAllReports(std.testing.io, &state, &cfg, null, &.{}, alloc, null);
    }

    // Changed file between flushes: the memo must replace (not leak) the old result.
    var py = state.file_entries.getPtr("src/main.py").?;
    py.content = @constCast("def a():\n    return 1\n");
    py.mtime = 1;
    writeAllReports(std.testing.io, &state, &cfg, null, &.{}, alloc, null);

    // Deleted file: the memo sweep must free its cached result.
    _ = state.file_entries.remove("src/util.zig");
    writeAllReports(std.testing.io, &state, &cfg, null, &.{}, alloc, null);
}
