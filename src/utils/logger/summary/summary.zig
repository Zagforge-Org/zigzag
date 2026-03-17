const std = @import("std");
const colors = @import("../../colors/colors.zig");

/// Arguments for printSummary. Avoids a long parameter list and a dependency on ProcessStats.
pub const SummaryArgs = struct {
    path: []const u8,
    total: usize,
    source: usize,
    cached: usize,
    fresh: usize,
    binary: usize,
    ignored: usize,
};

/// Prints a colored summary block to stderr.
pub fn printSummary(args: SummaryArgs) void {
    // On TTY the ProgressBar's success line already shows scanned count; skip the full block.
    if (std.posix.isatty(std.fs.File.stderr().handle)) return;
    var buf: [4096]u8 = undefined;
    var pos: usize = 0;
    pos += (std.fmt.bufPrint(buf[pos..], "\n{s} ══ Summary: {s}{s}{s} ══{s}\n", .{
        colors.colorCode(.BrightCyan),
        colors.colorCode(.BrightWhite),
        args.path,
        colors.colorCode(.BrightCyan),
        colors.colorCode(.Reset),
    }) catch return).len;
    pos += (std.fmt.bufPrint(buf[pos..], "    Total:   {d} files\n", .{args.total}) catch return).len;
    pos += (std.fmt.bufPrint(buf[pos..], "    Source:  {d}  (cached: {d}, fresh: {d})\n", .{ args.source, args.cached, args.fresh }) catch return).len;
    pos += (std.fmt.bufPrint(buf[pos..], "    Binary:  {d}\n", .{args.binary}) catch return).len;
    pos += (std.fmt.bufPrint(buf[pos..], "    Ignored: {d}\n", .{args.ignored}) catch return).len;
    std.fs.File.stderr().writeAll(buf[0..pos]) catch {};
}
