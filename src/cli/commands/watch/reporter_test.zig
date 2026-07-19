const std = @import("std");
const State = @import("state.zig").State;
const JobEntry = @import("../../../jobs/entries.zig").JobEntry;
const BinaryEntry = @import("../../../jobs/entries.zig").BinaryEntry;
const Config = @import("../config/config.zig").Config;
const writeAllReports = @import("reporter.zig").writeAllReports;

fn makeState(
    alloc: std.mem.Allocator,
    md_path: []const u8,
) State {
    var state: State = undefined;
    state.root_path = "src";
    state.md_path = md_path;
    state.file_entries = std.StringHashMap(JobEntry).init(alloc);
    state.binary_entries = std.StringHashMap(BinaryEntry).init(alloc);
    state.entries_mutex = .init;
    state.allocator = alloc;
    state.file_ctx = .{ .io = std.testing.io, .ignore_list = .empty, .md = undefined, .md_mutex = undefined };
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

    var cfg = Config.default(alloc);
    defer cfg.deinit();

    writeAllReports(std.testing.io, &state, &cfg, null, &.{}, alloc);

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

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    cfg.json_output = true;

    writeAllReports(std.testing.io, &state, &cfg, null, &.{}, alloc);

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

    var cfg = Config.default(alloc);
    defer cfg.deinit();
    cfg.html_output = true;

    writeAllReports(std.testing.io, &state, &cfg, null, &.{}, alloc);

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

    writeAllReports(std.testing.io, &state, &cfg, null, &.{}, alloc);

    const content = try tmp.dir.readFileAlloc(std.testing.io, "report.md", alloc, .limited(1 << 20));
    defer alloc.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "src/main.zig") != null);
}
