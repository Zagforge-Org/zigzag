const std = @import("std");
const colors = @import("../../colors.zig");

// Colored terminal output
// Each helper writes a colored prefix then the caller's format string.
// We build the full message in a stack buffer and write it in one shot so
// interleaved calls from different goroutines don't produce garbled output.

fn stderrWrite(buf: []u8, comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.bufPrint(buf, fmt, args) catch return;
    std.fs.File.stderr().writeAll(msg) catch {};
}

pub fn printStep(comptime fmt: []const u8, args: anytype) void {
    var buf: [2048]u8 = undefined;
    var pos: usize = 0;
    pos += (std.fmt.bufPrint(buf[pos..], "{s} › {s}", .{
        colors.colorCode(.BrightCyan), colors.colorCode(.Reset),
    }) catch return).len;
    pos += (std.fmt.bufPrint(buf[pos..], fmt ++ "\n", args) catch return).len;
    std.fs.File.stderr().writeAll(buf[0..pos]) catch {};
}

pub fn printSuccess(comptime fmt: []const u8, args: anytype) void {
    var buf: [2048]u8 = undefined;
    var pos: usize = 0;
    pos += (std.fmt.bufPrint(buf[pos..], "{s} ✓ {s}", .{
        colors.colorCode(.BrightGreen), colors.colorCode(.Reset),
    }) catch return).len;
    pos += (std.fmt.bufPrint(buf[pos..], fmt ++ "\n", args) catch return).len;
    std.fs.File.stderr().writeAll(buf[0..pos]) catch {};
}

pub fn printError(comptime fmt: []const u8, args: anytype) void {
    var buf: [2048]u8 = undefined;
    var pos: usize = 0;
    pos += (std.fmt.bufPrint(buf[pos..], "{s} ✗ {s}", .{
        colors.colorCode(.BrightRed), colors.colorCode(.Reset),
    }) catch return).len;
    pos += (std.fmt.bufPrint(buf[pos..], fmt ++ "\n", args) catch return).len;
    std.fs.File.stderr().writeAll(buf[0..pos]) catch {};
}

pub fn printWarn(comptime fmt: []const u8, args: anytype) void {
    var buf: [2048]u8 = undefined;
    var pos: usize = 0;
    pos += (std.fmt.bufPrint(buf[pos..], "{s} ⚠ {s}", .{
        colors.colorCode(.BrightYellow), colors.colorCode(.Reset),
    }) catch return).len;
    pos += (std.fmt.bufPrint(buf[pos..], fmt ++ "\n", args) catch return).len;
    std.fs.File.stderr().writeAll(buf[0..pos]) catch {};
}

/// Prints a colored summary block to stderr.
/// Takes plain values so the logger module has no dependency on ProcessStats.
pub fn printSummary(path: []const u8, total: usize, source: usize, cached: usize, fresh: usize, binary: usize, ignored: usize) void {
    var buf: [4096]u8 = undefined;
    var pos: usize = 0;
    pos += (std.fmt.bufPrint(buf[pos..], "\n{s} ══ Summary: {s}{s}{s} ══{s}\n", .{
        colors.colorCode(.BrightCyan),
        colors.colorCode(.BrightWhite),
        path,
        colors.colorCode(.BrightCyan),
        colors.colorCode(.Reset),
    }) catch return).len;
    pos += (std.fmt.bufPrint(buf[pos..], "    Total:   {d} files\n", .{total}) catch return).len;
    pos += (std.fmt.bufPrint(buf[pos..], "    Source:  {d}  (cached: {d}, fresh: {d})\n", .{ source, cached, fresh }) catch return).len;
    pos += (std.fmt.bufPrint(buf[pos..], "    Binary:  {d}\n", .{binary}) catch return).len;
    pos += (std.fmt.bufPrint(buf[pos..], "    Ignored: {d}\n", .{ignored}) catch return).len;
    std.fs.File.stderr().writeAll(buf[0..pos]) catch {};
}

// File logger

/// Writes timestamped plain-text log entries to a file inside the output dir.
/// Created via Logger.init(); must be deinitialized with Logger.deinit().
pub const Logger = struct {
    file: std.fs.File,

    /// Opens (or creates) `<output_dir>/zigzag.log` in append mode.
    pub fn init(output_dir: []const u8, allocator: std.mem.Allocator) !Logger {
        std.fs.cwd().makePath(output_dir) catch {};
        const log_path = try std.fs.path.join(allocator, &.{ output_dir, "zigzag.log" });
        defer allocator.free(log_path);
        const f = try std.fs.cwd().createFile(log_path, .{ .truncate = false });
        try f.seekFromEnd(0);
        return .{ .file = f };
    }

    pub fn deinit(self: *Logger) void {
        self.file.close();
    }

    /// Writes a timestamped line to the log file.
    pub fn log(self: Logger, comptime fmt: []const u8, args: anytype) void {
        const ts_raw = std.time.timestamp();
        const ts: u64 = if (ts_raw > 0) @intCast(ts_raw) else 0;
        const es = std.time.epoch.EpochSeconds{ .secs = ts };
        const ed = es.getEpochDay();
        const yd = ed.calculateYearDay();
        const md = yd.calculateMonthDay();
        const ds = es.getDaySeconds();

        var buf: [2048]u8 = undefined;
        const msg = std.fmt.bufPrint(
            &buf,
            "[{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}] " ++ fmt ++ "\n",
            .{
                yd.year,
                md.month.numeric(),
                md.day_index + 1,
                ds.getHoursIntoDay(),
                ds.getMinutesIntoHour(),
                ds.getSecondsIntoMinute(),
            } ++ args,
        ) catch return;
        self.file.writeAll(msg) catch {};
    }
};
