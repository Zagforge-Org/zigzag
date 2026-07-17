const std = @import("std");
const rt = @import("../../../runtime.zig");
const colors = @import("../../colors/colors.zig");

pub fn stderrWrite(buf: []u8, comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.bufPrint(buf, fmt, args) catch return;
    std.Io.File.stderr().writeStreamingAll(rt.io(), msg) catch {};
}

/// Dim horizontal rule — same width as the ProgressBar separator.
pub fn printSeparator() void {
    std.Io.File.stderr().writeStreamingAll(rt.io(), "\x1b[90m" ++ "─" ** 36 ++ "\x1b[0m\n") catch {};
}

pub fn printStep(comptime fmt: []const u8, args: anytype) void {
    var buf: [2048]u8 = undefined;
    var pos: usize = 0;
    pos += (std.fmt.bufPrint(buf[pos..], "{s} › {s}", .{
        colors.colorCode(.BrightCyan), colors.colorCode(.Reset),
    }) catch return).len;
    pos += (std.fmt.bufPrint(buf[pos..], fmt ++ "\n", args) catch return).len;
    std.Io.File.stderr().writeStreamingAll(rt.io(), buf[0..pos]) catch {};
}

pub fn printSuccess(comptime fmt: []const u8, args: anytype) void {
    var buf: [2048]u8 = undefined;
    var pos: usize = 0;
    pos += (std.fmt.bufPrint(buf[pos..], "{s} ✓ {s}", .{
        colors.colorCode(.BrightGreen), colors.colorCode(.Reset),
    }) catch return).len;
    pos += (std.fmt.bufPrint(buf[pos..], fmt ++ "\n", args) catch return).len;
    std.Io.File.stderr().writeStreamingAll(rt.io(), buf[0..pos]) catch {};
}

pub fn printError(comptime fmt: []const u8, args: anytype) void {
    var buf: [2048]u8 = undefined;
    var pos: usize = 0;
    pos += (std.fmt.bufPrint(buf[pos..], "{s} ✗ {s}", .{
        colors.colorCode(.BrightRed), colors.colorCode(.Reset),
    }) catch return).len;
    pos += (std.fmt.bufPrint(buf[pos..], fmt ++ "\n", args) catch return).len;
    std.Io.File.stderr().writeStreamingAll(rt.io(), buf[0..pos]) catch {};
}

pub fn printWarn(comptime fmt: []const u8, args: anytype) void {
    var buf: [2048]u8 = undefined;
    var pos: usize = 0;
    pos += (std.fmt.bufPrint(buf[pos..], "{s} ⚠ {s}", .{
        colors.colorCode(.BrightYellow), colors.colorCode(.Reset),
    }) catch return).len;
    pos += (std.fmt.bufPrint(buf[pos..], fmt ++ "\n", args) catch return).len;
    std.Io.File.stderr().writeStreamingAll(rt.io(), buf[0..pos]) catch {};
}
