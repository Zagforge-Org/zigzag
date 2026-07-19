//! Stack-allocated stderr writer: owns stderr, its `io` handle, and a scratch
//! buffer.

const std = @import("std");
const builtin = @import("builtin");
const Style = @import("Style.zig");

const Self = @This();

// Test builds never write to the real console: it desyncs `zig build test`'s
// --listen IPC (spurious `failed command:`). `test_sink` optionally captures the
// output instead. See test-stdout-listen-trap.
var test_sink: ?*std.Io.Writer = null;

pub fn setTestSink(sink: ?*std.Io.Writer) void {
    test_sink = sink;
}

file: std.Io.File,
io: std.Io,
buf: [4096]u8 = undefined,

pub fn init(io: std.Io) Self {
    return .{
        .io = io,
        .file = .stderr(),
    };
}

pub fn isTty(self: *Self) bool {
    if (builtin.is_test) return false;
    return self.file.isTty(self.io) catch false;
}

pub fn write(self: *Self, bytes: []const u8) void {
    if (test_sink) |w| {
        w.writeAll(bytes) catch {};
        return;
    }
    if (builtin.is_test) return;
    self.file.writeStreamingAll(self.io, bytes) catch {};
}

pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.bufPrint(&self.buf, fmt, args) catch return;
    self.write(msg);
}

/// Same width as the Progress separator.
pub fn separator(self: *Self) void {
    self.write(Style.rule);
}

/// Bold section title wrapped in 40-column section rules.
pub fn sectionHeader(self: *Self, title: []const u8) void {
    self.write(Style.section);
    self.print("{s} {s}{s}\n", .{ Style.bold, title, Style.reset });
    self.write(Style.section);
}

/// Colon-aligned key/value row: ` Label          : value`.
pub fn labelValue(self: *Self, label: []const u8, value: []const u8) void {
    self.print(" {s:<14} : {s}\n", .{ label, value });
}

/// Green-check entry: ` ✔  name`.
pub fn successLine(self: *Self, name: []const u8) void {
    self.print(" {s}{s}{s}  {s}\n", .{ Style.green, Style.check, Style.reset, name });
}

/// Colon-aligned bullet row: ` • Label         : value`.
pub fn bulletLine(self: *Self, label: []const u8, value: []const u8) void {
    self.print(" {s}{s}{s} {s:<17} : {s}\n", .{ Style.dim, Style.bullet, Style.reset, label, value });
}

/// Phase-breakdown row: ` Name             : duration     (pct%)`, `<1%` at zero.
pub fn phaseRow(self: *Self, name: []const u8, duration: []const u8, pct: u64) void {
    if (pct == 0)
        self.print(" {s:<16} : {s:<12} (<1%)\n", .{ name, duration })
    else
        self.print(" {s:<16} : {s:<12} ({d}%)\n", .{ name, duration, pct });
}
