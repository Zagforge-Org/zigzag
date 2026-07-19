//! Renders the per-phase timing table to stderr.

const std = @import("std");
const options = @import("options");

const BenchResult = @import("BenchResult.zig");
const Aggregator = @import("Aggregator.zig");
const lg = @import("../../../utils/utils.zig");
const host = @import("../../../utils/host.zig");

const Self = @This();

const separator = "  ──────────────────────────────────────────────────────────";

result: *const BenchResult,
total_ns: u64,

pub fn init(result: *const BenchResult) Self {
    return .{ .result = result, .total_ns = result.totalNs() };
}

/// Prints the table to stderr. Phases with zero duration are omitted.
pub fn print(self: Self, io: std.Io) void {
    if (self.total_ns == 0) return;

    var buf: [4096]u8 = undefined;
    var file_writer = std.Io.File.stderr().writer(io, &buf);
    const w = &file_writer.interface;
    self.write(io, w) catch return;
    w.flush() catch {};
}

pub fn write(self: Self, io: std.Io, w: *std.Io.Writer) !void {
    const cpu_count = std.Thread.getCpuCount() catch 0;
    var cpu_name_buf: [128]u8 = undefined;
    const cpu_name = host.getCpuName(io, &cpu_name_buf);
    const cpu_s: []const u8 = if (cpu_count == 1) "" else "s";

    try w.print("\n  Machine : {s} {s} · {d} core{s}\n", .{ host.getOs(), host.getArch(), cpu_count, cpu_s });
    try w.print("  CPU     : {s}\n", .{cpu_name});
    try w.print("  ZigZag  : {s}\n\n", .{options.version_string});

    try w.print("\n{s}\n", .{separator});
    try w.print("  {s:<16} {s:>10}   {s:<24} {s:>8}\n", .{ "Phase", "Duration", "Context", "% Total" });
    try w.print("{s}\n", .{separator});

    const agg = Aggregator.init(self.result, self.total_ns);
    var ctx_buf: [32]u8 = undefined;
    for (Aggregator.Metric.all) |metric|
        try agg.writeMetric(w, metric, &ctx_buf);

    var dur_buf: [16]u8 = undefined;
    try w.print("{s}\n", .{separator});
    try w.print("  {s:<16} {s:>10}\n\n", .{ "total", lg.fmtDuration(&dur_buf, self.total_ns) });
}
