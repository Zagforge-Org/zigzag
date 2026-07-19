//! renders the final multi-section report to stderr.

const std = @import("std");
const options = @import("options");
const fmt = @import("../utils/fmt/fmt.zig");
const host = @import("../utils/host.zig");
const Style = @import("Style.zig");
const ConsoleWriter = @import("ConsoleWriter.zig");
const Phase = @import("Phase.zig");
const stats = @import("ReportStats.zig");

pub const FinalSummary = @import("FinalSummary.zig");

pub fn finalSummary(io: std.Io, data: *const FinalSummary) void {
    var cw = ConsoleWriter.init(io);
    const totals = stats.totals(data);

    renderHeader(&cw);
    renderSummary(&cw, data);
    renderPhaseBreakdown(&cw, &totals);
    renderGeneratedReports(&cw, data);
    renderHighlights(&cw, &totals, data.md_bytes);
    renderFooter(&cw);
}

fn renderHeader(cw: *ConsoleWriter) void {
    cw.print("\n{s}{s}{s} ZigZag — Report Generation Complete{s}\n\n", .{
        Style.bold,
        Style.white,
        Style.rocket,
        Style.reset,
    });
}

fn renderSummary(cw: *ConsoleWriter, data: *const FinalSummary) void {
    cw.sectionHeader("Summary");

    const cpu_count = std.Thread.getCpuCount() catch 0;
    var cpu_name_buf: [128]u8 = undefined;
    var value_buf: [128]u8 = undefined;
    var elapsed_buf: [32]u8 = undefined;
    var files_buf: [32]u8 = undefined;

    const cpu_s: []const u8 = if (cpu_count == 1) "" else "s";
    const machine = std.fmt.bufPrint(&value_buf, "{s} {s} ({d} core{s})", .{
        host.getOs(),
        host.getArch(),
        cpu_count,
        cpu_s,
    }) catch value_buf[0..0];
    cw.labelValue("Machine", machine);
    cw.labelValue("CPU", host.getCpuName(cw.io, &cpu_name_buf));
    cw.labelValue("ZigZag Version", options.version_string);
    cw.labelValue("Total Time", fmt.fmtElapsed(&elapsed_buf, data.total_ns));
    cw.write("\n");

    cw.labelValue("Files Scanned", fmt.fmtThousands(&files_buf, data.files_total));

    const n_proj = data.path_names.len;
    const proj_word: []const u8 = if (n_proj == 1) "project" else "projects";
    const combined_suffix: []const u8 = if (data.has_combined) " + combined" else "";
    const reports = std.fmt.bufPrint(&value_buf, "{d} {s}{s}", .{
        n_proj,
        proj_word,
        combined_suffix,
    }) catch value_buf[0..0];
    cw.labelValue("Reports Built", reports);
    cw.write("\n");
}

fn renderPhaseBreakdown(cw: *ConsoleWriter, totals: *const stats.Totals) void {
    cw.sectionHeader("Phase Breakdown");
    var elapsed_buf: [32]u8 = undefined;
    for (totals.phases) |pt| {
        if (pt.ns == 0) continue;
        cw.phaseRow(pt.phase.display, fmt.fmtElapsed(&elapsed_buf, pt.ns), pt.pct);
    }
    cw.write("\n");
}

fn renderGeneratedReports(cw: *ConsoleWriter, data: *const FinalSummary) void {
    if (data.path_names.len == 0) return;
    cw.sectionHeader("Generated Reports");
    for (data.path_names) |name| cw.successLine(name);
    if (data.has_combined) cw.successLine("combined");
    cw.write("\n");
}

fn renderHighlights(cw: *ConsoleWriter, totals: *const stats.Totals, md_bytes: u64) void {
    cw.sectionHeader("Highlights");
    const h = stats.highlights(totals, md_bytes);
    var value_buf: [64]u8 = undefined;

    if (h.largest) |workload| {
        const v = std.fmt.bufPrint(&value_buf, "{s} ({d}% of total)", .{
            workload.name,
            workload.pct,
        }) catch value_buf[0..0];
        cw.bulletLine("Largest workload", v);
    }
    if (h.markdown_bytes > 0) {
        var bytes_buf: [32]u8 = undefined;
        const v = std.fmt.bufPrint(&value_buf, "{s} generated", .{
            fmt.fmtBytes(&bytes_buf, h.markdown_bytes, false),
        }) catch value_buf[0..0];
        cw.bulletLine("Markdown output", v);
    }
    if (h.fastest) |step| {
        var elapsed_buf: [32]u8 = undefined;
        const v = std.fmt.bufPrint(&value_buf, "{s} ({s})", .{
            step.name,
            fmt.fmtElapsed(&elapsed_buf, step.ns),
        }) catch value_buf[0..0];
        cw.bulletLine("Fastest step", v);
    }
    cw.write("\n");
}

fn renderFooter(cw: *ConsoleWriter) void {
    cw.write(Style.section);
    cw.print(" {s}{s} All paths processed successfully{s}\n", .{ Style.green, Style.badge, Style.reset });
}
