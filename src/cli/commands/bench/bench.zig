const std = @import("std");
const builtin = @import("builtin");
const options = @import("options");
const Config = @import("../config/config.zig").Config;
const Cache = @import("../../../cache/Cache.zig");
const runner = @import("../runner.zig");
const lg = @import("../../../utils/utils.zig");
const fmt_utils = @import("../../../utils/utils.zig");

const sep = "  ──────────────────────────────────────────────────────────";

pub fn execBench(io: std.Io, cfg: *const Config, allocator: std.mem.Allocator) !void {
    const cache_path = try std.fs.path.join(allocator, &.{ ".", ".cache" });
    defer allocator.free(cache_path);

    lg.printStep("Loading cache...", .{});
    var cache = try Cache.init(allocator, io, cache_path, cfg.small_threshold);
    defer cache.deinit();
    if (cache.entryCount() > 0)
        lg.printSuccess("Cache: {d} entries", .{cache.entryCount()});

    var result: runner.BenchResult = .{};
    try runner.exec(cfg, &cache, allocator, &result);
    printTable(io, &result);
}

/// Prints a per-phase timing table to stderr.
/// Phases with zero duration are omitted.
pub fn printTable(io: std.Io, result: *const runner.BenchResult) void {
    const total_ns = result.scan_ns + result.aggregate_ns +
        result.write_md_ns + result.write_json_ns +
        result.write_html_ns + result.write_llm_ns;
    if (total_ns == 0) return;

    var buf: [4096]u8 = undefined;
    var file_writer = std.Io.File.stderr().writer(io, &buf);
    const w = &file_writer.interface;
    writeTable(w, result, total_ns) catch return;
    w.flush() catch {};
}

fn writeTable(w: *std.Io.Writer, result: *const runner.BenchResult, total_ns: u64) !void {
    const os_name = comptime switch (builtin.os.tag) {
        .linux => "Linux",
        .macos => "macOS",
        .windows => "Windows",
        else => @tagName(builtin.os.tag),
    };
    const arch_name = comptime switch (builtin.cpu.arch) {
        .x86_64 => "x86_64",
        .aarch64 => "arm64",
        else => @tagName(builtin.cpu.arch),
    };

    const cpu_count = std.Thread.getCpuCount() catch 0;
    var cpu_name_buf: [128]u8 = undefined;
    const cpu_name = lg.getCpuName(&cpu_name_buf);
    const cpu_s: []const u8 = if (cpu_count == 1) "" else "s";

    try w.print("\n  Machine : {s} {s} · {d} core{s}\n", .{ os_name, arch_name, cpu_count, cpu_s });
    try w.print("  CPU     : {s}\n", .{cpu_name});
    try w.print("  ZigZag  : {s}\n\n", .{options.version_string});

    try w.print("\n{s}\n", .{sep});
    try w.print("  {s:<16} {s:>10}   {s:<24} {s:>8}\n", .{ "Phase", "Duration", "Context", "% Total" });
    try w.print("{s}\n", .{sep});

    var ctx_buf: [32]u8 = undefined;
    if (result.scan_ns > 0)
        try writeRow(w, "scan", result.scan_ns, total_ns, try std.fmt.bufPrint(&ctx_buf, "{d} files", .{result.files_total}));
    if (result.aggregate_ns > 0)
        try writeRow(w, "aggregate", result.aggregate_ns, total_ns, try std.fmt.bufPrint(&ctx_buf, "{d} entries", .{result.files_source}));
    if (result.write_md_ns > 0)
        try writeRow(w, "write-md", result.write_md_ns, total_ns, fmt_utils.fmtBytes(&ctx_buf, result.md_bytes, false));
    if (result.write_json_ns > 0)
        try writeRow(w, "write-json", result.write_json_ns, total_ns, fmt_utils.fmtBytes(&ctx_buf, result.json_bytes, false));
    if (result.write_html_ns > 0)
        try writeRow(w, "write-html", result.write_html_ns, total_ns, fmt_utils.fmtBytes(&ctx_buf, result.html_bytes, true));
    if (result.write_llm_ns > 0)
        try writeRow(w, "write-llm", result.write_llm_ns, total_ns, fmt_utils.fmtBytes(&ctx_buf, result.llm_bytes, false));

    var dur_buf: [16]u8 = undefined;
    try w.print("{s}\n", .{sep});
    try w.print("  {s:<16} {s:>10}\n\n", .{ "total", fmtDuration(&dur_buf, total_ns) });
}

fn writeRow(w: *std.Io.Writer, name: []const u8, phase_ns: u64, total_ns: u64, ctx: []const u8) !void {
    var dur_buf: [16]u8 = undefined;
    const pct = phase_ns * 100 / total_ns;
    try w.print("  {s:<16} {s:>10}   {s:<24} {d:>7}%\n", .{ name, fmtDuration(&dur_buf, phase_ns), ctx, pct });
}

/// Formats a nanosecond duration as "< 1 ms" (sub-millisecond) or "{d} ms".
fn fmtDuration(buf: []u8, ns: u64) []const u8 {
    const ms = ns / 1_000_000;
    if (ms == 0) return "< 1 ms";
    return std.fmt.bufPrint(buf, "{d} ms", .{ms}) catch "? ms";
}
