//! ConsoleLogger — line-oriented stderr UI (steps, status glyphs, phase timing).

const std = @import("std");
const colors = @import("../colors/colors.zig");
const fmt = @import("../fmt/fmt.zig");
const console = @import("../../platform/console.zig");
const ConsoleWriter = @import("ConsoleWriter.zig");
const LineWriter = @import("LineWriter.zig");

threadlocal var phase_buf: [256]u8 = undefined;
threadlocal var phase_len: usize = 0;

/// A status glyph and its color, prepended to a message line.
const Prefix = struct { color: []const u8, glyph: []const u8 };

const Messages = struct {
    const step = Prefix{ .color = colors.colorCode(.BrightCyan), .glyph = " › " };
    const success = Prefix{ .color = colors.colorCode(.BrightGreen), .glyph = " ✓ " };
    const err = Prefix{ .color = colors.colorCode(.BrightRed), .glyph = " ✗ " };
    const warn = Prefix{ .color = colors.colorCode(.BrightYellow), .glyph = " ⚠ " };
};

fn message(io: std.Io, prefix: Prefix, comptime fmt_str: []const u8, args: anytype) void {
    var cw = ConsoleWriter.init(io);
    cw.print("{s}{s}{s}" ++ fmt_str ++ "\n", .{ prefix.color, prefix.glyph, colors.colorCode(.Reset) } ++ args);
}

pub fn separator(io: std.Io) void {
    var cw = ConsoleWriter.init(io);
    cw.separator();
}

pub fn step(io: std.Io, comptime fmt_str: []const u8, args: anytype) void {
    message(io, Messages.step, fmt_str, args);
}

pub fn success(io: std.Io, comptime fmt_str: []const u8, args: anytype) void {
    message(io, Messages.success, fmt_str, args);
}

pub fn err(io: std.Io, comptime fmt_str: []const u8, args: anytype) void {
    message(io, Messages.err, fmt_str, args);
}

pub fn warn(io: std.Io, comptime fmt_str: []const u8, args: anytype) void {
    message(io, Messages.warn, fmt_str, args);
}

pub fn phaseStart(
    io: std.Io,
    comptime fmt_str: []const u8,
    args: anytype,
) void {
    phase_len = if (std.fmt.bufPrint(&phase_buf, fmt_str, args)) |w| w.len else |_| 0;

    var cw = ConsoleWriter.init(io);

    cw.print(
        "{s} › {s}{s}\n",
        .{
            colors.colorCode(.BrightCyan),
            colors.colorCode(.Reset),
            phase_buf[0..phase_len],
        },
    );
}

pub fn phaseDone(
    io: std.Io,
    elapsed_ns: u64,
    comptime context_fmt: []const u8,
    context_args: anytype,
) void {
    var cw = ConsoleWriter.init(io);
    var line = LineWriter.init(&cw.buf);

    const is_tty = cw.isTty();

    var elapsed_buf: [32]u8 = undefined;
    const elapsed = fmt.fmtElapsed(&elapsed_buf, elapsed_ns);

    if (is_tty) {
        console.enableAnsi();

        line.write("\x1B[1A\r\x1B[2K");
        line.write(colors.colorCode(.BrightCyan));
        line.write(" › ");
        line.write(colors.colorCode(.Reset));

        line.write(phase_buf[0..phase_len]);

        const visible = 3 + phase_len;
        line.pad(if (visible < 40) 40 - visible else 2);
    }

    line.write("done  ");
    line.write(elapsed);

    if (comptime context_fmt.len > 0) {
        line.write("  (");
        line.writeFmt(context_fmt, context_args);
        line.write(")");
    }

    line.write("\n");

    cw.write(line.slice());
}
