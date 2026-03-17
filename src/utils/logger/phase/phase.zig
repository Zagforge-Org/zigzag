const std = @import("std");
const builtin = @import("builtin");
const colors = @import("../../colors/colors.zig");
const fmt_utils = @import("../../fmt/fmt.zig");
const cpu = @import("../cpu/cpu.zig");

// Stores the last printPhaseStart text so printPhaseDone can reprint the full line on TTY.
threadlocal var g_phase_buf: [256]u8 = undefined;
threadlocal var g_phase_len: usize = 0;

pub fn printPhaseStart(comptime fmt: []const u8, args: anytype) void {
    // Store the phase label (without color codes) for printPhaseDone to reprint.
    const label = std.fmt.bufPrint(&g_phase_buf, fmt, args) catch &g_phase_buf;
    g_phase_len = label.len;

    var buf: [4096]u8 = undefined;
    var pos: usize = 0;
    pos += (std.fmt.bufPrint(buf[pos..], "{s} › {s}", .{
        colors.colorCode(.BrightCyan), colors.colorCode(.Reset),
    }) catch return).len;
    pos += (std.fmt.bufPrint(buf[pos..], fmt, args) catch return).len;
    pos += (std.fmt.bufPrint(buf[pos..], "\n", .{}) catch return).len;
    std.fs.File.stderr().writeAll(buf[0..pos]) catch {};
}

pub fn printPhaseDone(elapsed_ns: u64, comptime context_fmt: []const u8, context_args: anytype) void {
    const is_tty = std.posix.isatty(std.fs.File.stderr().handle);
    var buf: [4096]u8 = undefined;
    var elapsed_buf: [32]u8 = undefined;
    const elapsed = fmt_utils.fmtElapsed(elapsed_ns, &elapsed_buf);
    var pos: usize = 0;
    if (is_tty) {
        // On Windows, enable virtual terminal processing so ANSI escapes work.
        if (comptime builtin.os.tag == .windows) {
            const windows = std.os.windows;
            var mode: windows.DWORD = 0;
            if (windows.kernel32.GetConsoleMode(std.fs.File.stderr().handle, &mode) != 0) {
                _ = windows.kernel32.SetConsoleMode(
                    std.fs.File.stderr().handle,
                    mode | 0x0004, // ENABLE_VIRTUAL_TERMINAL_PROCESSING
                );
            }
        }
        pos += (std.fmt.bufPrint(buf[pos..], "\x1B[1A\r\x1B[2K", .{}) catch return).len;
        pos += (std.fmt.bufPrint(buf[pos..], "{s} › {s}", .{
            colors.colorCode(.BrightCyan), colors.colorCode(.Reset),
        }) catch return).len;
        const stored = g_phase_buf[0..g_phase_len];
        pos += (std.fmt.bufPrint(buf[pos..], "{s}", .{stored}) catch return).len;
        const visible: usize = 3 + g_phase_len;
        const pad: usize = if (visible < 40) 40 - visible else 2;
        var i: usize = 0;
        while (i < pad and pos < buf.len) : (i += 1) {
            buf[pos] = ' ';
            pos += 1;
        }
    }
    pos += (std.fmt.bufPrint(buf[pos..], "done  {s}", .{elapsed}) catch return).len;
    if (comptime context_fmt.len > 0) {
        pos += (std.fmt.bufPrint(buf[pos..], "  (", .{}) catch return).len;
        pos += (std.fmt.bufPrint(buf[pos..], context_fmt, context_args) catch return).len;
        pos += (std.fmt.bufPrint(buf[pos..], ")", .{}) catch return).len;
    }
    pos += (std.fmt.bufPrint(buf[pos..], "\n", .{}) catch return).len;
    std.fs.File.stderr().writeAll(buf[0..pos]) catch {};
}

pub const FinalSummaryData = struct {
    total_ns: u64,
    scan_ns: u64,
    aggregate_ns: u64,
    write_md_ns: u64,
    write_json_ns: u64,
    write_html_ns: u64,
    write_llm_ns: u64,
    files_total: usize,
    md_bytes: u64,
    path_names: []const []const u8,
    has_combined: bool,
};

pub fn printFinalSummary(data: *const FinalSummaryData) void {
    const options = @import("options");
    const stderr = std.fs.File.stderr();
    const sep = "\x1b[90m────────────────────────────────────────\x1b[0m\n";

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

    var buf: [512]u8 = undefined;
    var elapsed_buf: [32]u8 = undefined;
    var cpu_name_buf: [128]u8 = undefined;
    const cpu_name = cpu.getCpuName(&cpu_name_buf);

    // Header
    stderr.writeAll("\n\x1b[1m\x1b[97m🚀 ZigZag — Report Generation Complete\x1b[0m\n\n") catch {};

    // ── Summary ──
    stderr.writeAll(sep) catch {};
    stderr.writeAll("\x1b[1m Summary\x1b[0m\n") catch {};
    stderr.writeAll(sep) catch {};

    const cpu_s: []const u8 = if (cpu_count == 1) "" else "s";
    stderr.writeAll(std.fmt.bufPrint(&buf, " Machine        : {s} {s} ({d} core{s})\n", .{
        os_name, arch_name, cpu_count, cpu_s,
    }) catch return) catch {};
    stderr.writeAll(std.fmt.bufPrint(&buf, " CPU            : {s}\n", .{cpu_name}) catch return) catch {};
    stderr.writeAll(std.fmt.bufPrint(&buf, " ZigZag Version : {s}\n", .{options.version_string}) catch return) catch {};
    stderr.writeAll(std.fmt.bufPrint(&buf, " Total Time     : {s}\n", .{fmt_utils.fmtElapsed(data.total_ns, &elapsed_buf)}) catch return) catch {};
    stderr.writeAll("\n") catch {};

    var files_buf: [32]u8 = undefined;
    stderr.writeAll(std.fmt.bufPrint(&buf, " Files Scanned  : {s}\n", .{fmtThousands(data.files_total, &files_buf)}) catch return) catch {};

    const n_proj = data.path_names.len;
    const proj_word: []const u8 = if (n_proj == 1) "project" else "projects";
    const combined_suffix: []const u8 = if (data.has_combined) " + combined" else "";
    stderr.writeAll(std.fmt.bufPrint(&buf, " Reports Built  : {d} {s}{s}\n", .{ n_proj, proj_word, combined_suffix }) catch return) catch {};
    stderr.writeAll("\n") catch {};

    // ── Phase Breakdown ──
    const total_phase_ns = data.scan_ns + data.aggregate_ns +
        data.write_md_ns + data.write_json_ns +
        data.write_html_ns + data.write_llm_ns;

    stderr.writeAll(sep) catch {};
    stderr.writeAll("\x1b[1m Phase Breakdown\x1b[0m\n") catch {};
    stderr.writeAll(sep) catch {};

    const row: PhaseRowCtx = .{ .stderr = stderr, .total_ns = total_phase_ns, .buf = &buf };
    if (data.scan_ns > 0) row.append("Scan", data.scan_ns);
    if (data.aggregate_ns > 0) row.append("Aggregate", data.aggregate_ns);
    if (data.write_md_ns > 0) row.append("Write Markdown", data.write_md_ns);
    if (data.write_json_ns > 0) row.append("Write JSON", data.write_json_ns);
    if (data.write_html_ns > 0) row.append("Write HTML", data.write_html_ns);
    if (data.write_llm_ns > 0) row.append("Write LLM", data.write_llm_ns);
    stderr.writeAll("\n") catch {};

    // ── Generated Reports ──
    if (n_proj > 0) {
        stderr.writeAll(sep) catch {};
        stderr.writeAll("\x1b[1m Generated Reports\x1b[0m\n") catch {};
        stderr.writeAll(sep) catch {};
        for (data.path_names) |name| {
            stderr.writeAll(std.fmt.bufPrint(&buf, " \x1b[92m✔\x1b[0m  {s}\n", .{name}) catch continue) catch {};
        }
        if (data.has_combined) {
            stderr.writeAll(" \x1b[92m✔\x1b[0m  combined\n") catch {};
        }
        stderr.writeAll("\n") catch {};
    }

    // ── Highlights ──
    stderr.writeAll(sep) catch {};
    stderr.writeAll("\x1b[1m Highlights\x1b[0m\n") catch {};
    stderr.writeAll(sep) catch {};

    const PhaseInfo = struct { name: []const u8, ns: u64 };
    const phases = [_]PhaseInfo{
        .{ .name = "scan", .ns = data.scan_ns },
        .{ .name = "aggregation", .ns = data.aggregate_ns },
        .{ .name = "markdown writing", .ns = data.write_md_ns },
        .{ .name = "JSON writing", .ns = data.write_json_ns },
        .{ .name = "HTML writing", .ns = data.write_html_ns },
        .{ .name = "LLM writing", .ns = data.write_llm_ns },
    };
    var max_ns: u64 = 0;
    var max_name: []const u8 = "scan";
    var min_ns: u64 = std.math.maxInt(u64);
    var min_name: []const u8 = "";
    for (phases) |p| {
        if (p.ns > max_ns) { max_ns = p.ns; max_name = p.name; }
        if (p.ns > 0 and p.ns < min_ns) { min_ns = p.ns; min_name = p.name; }
    }

    if (total_phase_ns > 0) {
        const pct = max_ns * 100 / total_phase_ns;
        stderr.writeAll(std.fmt.bufPrint(&buf, " \x1b[90m•\x1b[0m Largest workload  : {s} ({d}% of total)\n", .{ max_name, pct }) catch return) catch {};
    }
    if (data.md_bytes > 0) {
        var ctx_buf: [32]u8 = undefined;
        stderr.writeAll(std.fmt.bufPrint(&buf, " \x1b[90m•\x1b[0m Markdown output   : {s} generated\n", .{fmt_utils.fmtBytes(&ctx_buf, data.md_bytes, false)}) catch return) catch {};
    }
    if (min_name.len > 0) {
        stderr.writeAll(std.fmt.bufPrint(&buf, " \x1b[90m•\x1b[0m Fastest step      : {s} ({s})\n", .{ min_name, fmt_utils.fmtElapsed(min_ns, &elapsed_buf) }) catch return) catch {};
    }
    stderr.writeAll("\n") catch {};

    // Footer
    stderr.writeAll(sep) catch {};
    stderr.writeAll(" \x1b[92m✅ All paths processed successfully\x1b[0m\n") catch {};
}

const PhaseRowCtx = struct {
    stderr: std.fs.File,
    total_ns: u64,
    buf: []u8,

    fn append(self: PhaseRowCtx, name: []const u8, phase_ns: u64) void {
        var elapsed_buf: [32]u8 = undefined;
        const dur = fmt_utils.fmtElapsed(phase_ns, &elapsed_buf);
        const pct = if (self.total_ns > 0) phase_ns * 100 / self.total_ns else 0;
        const line = if (pct == 0)
            std.fmt.bufPrint(self.buf, " {s:<16} : {s:<12} (<1%)\n", .{ name, dur }) catch return
        else
            std.fmt.bufPrint(self.buf, " {s:<16} : {s:<12} ({d}%)\n", .{ name, dur, pct }) catch return;
        self.stderr.writeAll(line) catch {};
    }
};

fn fmtThousands(n: usize, buf: []u8) []u8 {
    var tmp: [32]u8 = undefined;
    const s = std.fmt.bufPrint(&tmp, "{d}", .{n}) catch return buf[0..0];
    const len = s.len;
    var pos: usize = 0;
    for (s, 0..) |c, i| {
        const remaining = len - i;
        if (i > 0 and remaining % 3 == 0) {
            if (pos >= buf.len) break;
            buf[pos] = ',';
            pos += 1;
        }
        if (pos >= buf.len) break;
        buf[pos] = c;
        pos += 1;
    }
    return buf[0..pos];
}
