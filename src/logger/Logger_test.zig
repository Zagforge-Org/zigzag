const std = @import("std");
const log = @import("./Logger.zig");

const io = std.testing.io;

test "stderr UI helpers render into an injected sink" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    log.setTestSink(&aw.writer);
    defer log.setTestSink(null);

    log.separator(io);
    log.step(io, "test step {s}", .{"ok"});
    log.success(io, "done {d}", .{1});
    log.err(io, "failed {s}", .{"reason"});
    log.warn(io, "careful {s}", .{"now"});
    log.summary(io, .{
        .path = "./src",
        .total = 10,
        .source = 8,
        .cached = 5,
        .fresh = 3,
        .binary = 1,
        .ignored = 1,
    });
    log.phaseStart(io, "Scanning {s}...", .{"./src"});
    log.phaseDone(io, 148_000_000, "{d} files", .{42});
    log.phaseDone(io, 1_500_000_000, "", .{});

    const out = aw.written();
    try std.testing.expect(std.mem.indexOf(u8, out, "test step ok") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "careful now") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "42 files") != null);
}

test "finalSummary renders the full report into an injected sink" {
    const data = log.FinalSummary{
        .total_ns = 500_000_000,
        .scan_ns = 340_000_000,
        .aggregate_ns = 12_000_000,
        .write_md_ns = 8_000_000,
        .write_json_ns = 60_000_000,
        .write_html_ns = 45_000_000,
        .write_llm_ns = 0,
        .files_total = 1423,
        .md_bytes = 46_080,
        .path_names = &.{ "src", "lib" },
        .has_combined = true,
    };

    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    log.setTestSink(&aw.writer);
    defer log.setTestSink(null);

    log.finalSummary(io, &data);

    const out = aw.written();
    try std.testing.expect(std.mem.indexOf(u8, out, "ZigZag") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Phase Breakdown") != null);
}

test "file() no-ops when file logging is disabled" {
    try std.testing.expect(!log.fileEnabled());
    log.file(io, "this should be dropped {d}", .{1}); // must not panic
}

test "initFile creates log file and file() writes timestamped entries" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = path_buf[0..try tmp.dir.realPathFile(io, ".", &path_buf)];

    {
        try log.initFile(io, tmp_path, alloc);
        defer log.deinitFile(io);
        try std.testing.expect(log.fileEnabled());
        log.file(io, "hello {s}", .{"world"});
        log.file(io, "count {d}", .{42});
    }
    try std.testing.expect(!log.fileEnabled());

    const stat = try tmp.dir.statFile(io, "zigzag.log", .{});
    try std.testing.expect(stat.kind == .file);

    const content = try tmp.dir.readFileAlloc(io, "zigzag.log", alloc, .limited(4096));
    defer alloc.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "hello world") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "count 42") != null);
    try std.testing.expect(std.mem.startsWith(u8, content, "["));
}

test "initFile appends to an existing log file" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = path_buf[0..try tmp.dir.realPathFile(io, ".", &path_buf)];

    {
        try log.initFile(io, tmp_path, alloc);
        defer log.deinitFile(io);
        log.file(io, "first", .{});
    }
    {
        try log.initFile(io, tmp_path, alloc);
        defer log.deinitFile(io);
        log.file(io, "second", .{});
    }

    const content = try tmp.dir.readFileAlloc(io, "zigzag.log", alloc, .limited(4096));
    defer alloc.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "first") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "second") != null);
}
