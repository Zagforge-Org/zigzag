const std = @import("std");
const colors = @import("../../utils/colors");
const ConsoleWriter = @import("ConsoleWriter.zig");

const Self = @This();

color: colors.Color,
glyph: []const u8,

const Messages = struct {
    pub const step = Self{
        .color = .BrightCyan,
        .glyph = " › ",
    };

    pub const success = Self{
        .color = .BrightGreen,
        .glyph = " ✓ ",
    };

    pub const err = Self{
        .color = .BrightRed,
        .glyph = " ✗ ",
    };

    pub const warn = Self{
        .color = .BrightYellow,
        .glyph = " ⚠ ",
    };
};

fn message(
    io: std.Io,
    msg: Self,
    comptime fmt_str: []const u8,
    args: anytype,
) void {
    var cw = ConsoleWriter.init(io);

    cw.print(
        "{s}{s}{s}" ++ fmt_str ++ "\n",
        .{
            colors.colorCode(msg.color),
            msg.glyph,
            colors.colorCode(.Reset),
        } ++ args,
    );
}
