const std = @import("std");
const colors = @import("../../../utils/utils.zig");
const stdoutPrint = @import("../../../fs/stdout.zig").stdoutPrint;

pub const ascii_logo =
    \\
    \\
    \\$$$$$$$$\ $$\                 $$$$$$$$\
    \\____$$  |\__|                \____$$  |
    \\    $$  / $$\  $$$$$$\            $$  / $$$$$$\   $$$$$$\
    \\   $$  /  $$ |$$  __$$\          $$  /  \____$$\ $$  __$$\
    \\  $$  /   $$ |$$ /  $$ |        $$  /   $$$$$$$ |$$ /  $$ |
    \\ $$  /    $$ |$$ |  $$ |       $$  /   $$  __$$ |$$ |  $$ |
    \\$$$$$$$$\ $$ |\$$$$$$$ |      $$$$$$$$\\$$$$$$$ |\$$$$$$$ |
    \\________|\__| \____$$ |      \________|\_______| \____$$ |
    \\              $$\   $$ |                         $$\   $$ |
    \\              \$$$$$$  |                         \$$$$$$  |
    \\               \______/                           \______/
    \\
    \\
;

pub fn printAsciiLogo(io: std.Io) anyerror!void {
    try stdoutPrint(io, "{s}{s}{s}", .{
        colors.colorCode(colors.Color.Yellow),
        ascii_logo,
        colors.colorCode(colors.Color.Reset),
    });
}

/// writeAsciiLogo writes the logo to `w`. Separated from printAsciiLogo so
/// tests can exercise it against a buffer instead of the real stdout.
pub fn writeAsciiLogo(w: *std.Io.Writer) anyerror!void {
    try w.print("{s}{s}{s}", .{
        colors.colorCode(colors.Color.Yellow),
        ascii_logo,
        colors.colorCode(colors.Color.Reset),
    });
}
