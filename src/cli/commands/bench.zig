const std = @import("std");
const Config = @import("config/config.zig").Config;
const CacheImpl = @import("../../cache/impl.zig").CacheImpl;
const runner = @import("runner.zig");

pub fn execBench(cfg: *const Config, allocator: std.mem.Allocator) !void {
    const cache_path = try std.fs.path.join(allocator, &.{ ".", ".cache" });
    defer allocator.free(cache_path);

    var cache = try CacheImpl.init(allocator, cache_path, cfg.small_threshold);
    defer cache.deinit();

    var result: runner.BenchResult = .{};
    try runner.exec(cfg, &cache, allocator, &result);
    printTable(&result);
}

/// Prints a per-phase timing table to stderr.
/// Phases with zero duration are omitted.
pub fn printTable(result: *const runner.BenchResult) void {
    const total_ns = result.scan_ns + result.aggregate_ns +
        result.write_md_ns + result.write_json_ns +
        result.write_html_ns + result.write_llm_ns;
    if (total_ns == 0) return;

    const sep = "  ──────────────────────────────────────────────────────────";
    var buf: [4096]u8 = undefined;
    var pos: usize = 0;

    pos += (std.fmt.bufPrint(buf[pos..], "\n{s}\n", .{sep}) catch return).len;
    pos += (std.fmt.bufPrint(buf[pos..], "  {s:<16} {s:>10}   {s:<24} {s:>8}\n", .{
        "Phase", "Duration", "Context", "% Total",
    }) catch return).len;
    pos += (std.fmt.bufPrint(buf[pos..], "{s}\n", .{sep}) catch return).len;

    var ctx_buf: [32]u8 = undefined;

    if (result.scan_ns > 0) {
        const ctx = std.fmt.bufPrint(&ctx_buf, "{d} files", .{result.files_total}) catch "?";
        pos += appendRow(buf[pos..], "scan", result.scan_ns, total_ns, ctx) catch return;
    }
    if (result.aggregate_ns > 0) {
        const ctx = std.fmt.bufPrint(&ctx_buf, "{d} entries", .{result.files_source}) catch "?";
        pos += appendRow(buf[pos..], "aggregate", result.aggregate_ns, total_ns, ctx) catch return;
    }
    if (result.write_md_ns > 0) {
        const ctx = fmtBytes(&ctx_buf, result.md_bytes, false);
        pos += appendRow(buf[pos..], "write-md", result.write_md_ns, total_ns, ctx) catch return;
    }
    if (result.write_json_ns > 0) {
        const ctx = fmtBytes(&ctx_buf, result.json_bytes, false);
        pos += appendRow(buf[pos..], "write-json", result.write_json_ns, total_ns, ctx) catch return;
    }
    if (result.write_html_ns > 0) {
        const ctx = fmtBytes(&ctx_buf, result.html_bytes, true);
        pos += appendRow(buf[pos..], "write-html", result.write_html_ns, total_ns, ctx) catch return;
    }
    if (result.write_llm_ns > 0) {
        const ctx = fmtBytes(&ctx_buf, result.llm_bytes, false);
        pos += appendRow(buf[pos..], "write-llm", result.write_llm_ns, total_ns, ctx) catch return;
    }

    const total_ms = total_ns / 1_000_000;
    var dur_buf: [16]u8 = undefined;
    const total_dur: []const u8 = if (total_ms == 0)
        std.fmt.bufPrint(&dur_buf, "< 1 ms", .{}) catch "< 1 ms"
    else
        std.fmt.bufPrint(&dur_buf, "{d} ms", .{total_ms}) catch "? ms";

    pos += (std.fmt.bufPrint(buf[pos..], "{s}\n", .{sep}) catch return).len;
    pos += (std.fmt.bufPrint(buf[pos..], "  {s:<16} {s:>10}\n\n", .{ "total", total_dur }) catch return).len;

    std.fs.File.stderr().writeAll(buf[0..pos]) catch {};
}

/// Appends one table row into `buf`. Returns bytes written, or NoSpaceLeft.
fn appendRow(buf: []u8, name: []const u8, phase_ns: u64, total_ns: u64, ctx: []const u8) error{NoSpaceLeft}!usize {
    const ms = phase_ns / 1_000_000;
    const pct = phase_ns * 100 / total_ns;
    var dur_buf: [16]u8 = undefined;
    const dur: []const u8 = if (ms == 0)
        std.fmt.bufPrint(&dur_buf, "< 1 ms", .{}) catch "< 1 ms"
    else
        std.fmt.bufPrint(&dur_buf, "{d} ms", .{ms}) catch "? ms";
    const written = try std.fmt.bufPrint(buf,
        "  {s:<16} {s:>10}   {s:<24} {d:>7}%\n",
        .{ name, dur, ctx, pct });
    return written.len;
}

/// Formats `n` bytes as human-readable string into `buf`.
/// `html = true` appends " (w/ content)" to indicate the HTML content sidecar is included.
/// Returns a slice into `buf` — caller must not write to `buf` before consuming the result.
fn fmtBytes(buf: []u8, n: u64, html: bool) []const u8 {
    if (n == 0) return "—";
    const mb = @as(f64, @floatFromInt(n)) / (1024.0 * 1024.0);
    const kb = @as(f64, @floatFromInt(n)) / 1024.0;
    const suffix: []const u8 = if (html) " (w/ content)" else "";
    if (n >= 1024 * 1024)
        return std.fmt.bufPrint(buf, "{d:.1} MB{s}", .{ mb, suffix }) catch "?";
    if (n >= 1024)
        return std.fmt.bufPrint(buf, "{d:.1} KB{s}", .{ kb, suffix }) catch "?";
    return std.fmt.bufPrint(buf, "{d} B{s}", .{ n, suffix }) catch "?";
}
