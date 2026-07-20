const std = @import("std");
const colors = @import("../utils/colors/colors.zig");
const ConsoleWriter = @import("ConsoleWriter.zig");

const Self = @This();

path: []const u8,
total: usize,
source: usize,
cached: usize,
fresh: usize,
binary: usize,
ignored: usize,

/// Prints a colored summary block to stderr.
pub fn summary(io: std.Io, args: Self) void {
    var cw = ConsoleWriter.init(io);
    // On TTY the Progress success line already shows scanned count; skip the full block.
    if (cw.isTty()) return;
    cw.print("\n{s} ══ Summary: {s}{s}{s} ══{s}\n", .{
        colors.colorCode(.BrightCyan),
        colors.colorCode(.BrightWhite),
        args.path,
        colors.colorCode(.BrightCyan),
        colors.colorCode(.Reset),
    });
    cw.print("    Total:   {d} files\n", .{args.total});
    cw.print("    Source:  {d}  (cached: {d}, fresh: {d})\n", .{ args.source, args.cached, args.fresh });
    cw.print("    Binary:  {d}\n", .{args.binary});
    cw.print("    Ignored: {d}\n", .{args.ignored});
}
