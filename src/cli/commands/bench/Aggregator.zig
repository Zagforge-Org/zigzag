//! Writes per-phase metric rows into the timing table.

const std = @import("std");

const BenchResult = @import("BenchResult.zig");
const fmt_utils = @import("../../../utils/utils.zig");

const Self = @This();

pub const Metric = enum {
    scan,
    aggregate,
    write_md,
    write_json,
    write_html,
    write_llm,

    pub const all = [_]Metric{ .scan, .aggregate, .write_md, .write_json, .write_html, .write_llm };
};

result: *const BenchResult,
total_ns: u64,

pub fn init(result: *const BenchResult, total_ns: u64) Self {
    return .{ .result = result, .total_ns = total_ns };
}

pub fn writeMetric(self: Self, w: *std.Io.Writer, metric: Metric, ctx_buf: []u8) !void {
    const r = self.result;
    switch (metric) {
        .scan => if (r.scan_ns > 0)
            try self.writeRow(w, "scan", r.scan_ns, try std.fmt.bufPrint(ctx_buf, "{d} files", .{r.files_total})),
        .aggregate => if (r.aggregate_ns > 0)
            try self.writeRow(w, "aggregate", r.aggregate_ns, try std.fmt.bufPrint(ctx_buf, "{d} entries", .{r.files_source})),
        .write_md => if (r.write_md_ns > 0)
            try self.writeRow(w, "write-md", r.write_md_ns, fmt_utils.fmtBytes(ctx_buf, r.md_bytes, false)),
        .write_json => if (r.write_json_ns > 0)
            try self.writeRow(w, "write-json", r.write_json_ns, fmt_utils.fmtBytes(ctx_buf, r.json_bytes, false)),
        .write_html => if (r.write_html_ns > 0)
            try self.writeRow(w, "write-html", r.write_html_ns, fmt_utils.fmtBytes(ctx_buf, r.html_bytes, true)),
        .write_llm => if (r.write_llm_ns > 0)
            try self.writeRow(w, "write-llm", r.write_llm_ns, fmt_utils.fmtBytes(ctx_buf, r.llm_bytes, false)),
    }
}

fn writeRow(self: Self, w: *std.Io.Writer, name: []const u8, phase_ns: u64, ctx: []const u8) !void {
    var dur_buf: [16]u8 = undefined;
    const pct = phase_ns * 100 / self.total_ns;
    try w.print("  {s:<16} {s:>10}   {s:<24} {d:>7}%\n", .{ name, fmt_utils.fmtMilliseconds(&dur_buf, phase_ns), ctx, pct });
}
