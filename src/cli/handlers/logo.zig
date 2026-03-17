const colors = @import("../../utils/utils.zig");
const stdoutPrint = @import("../../fs/stdout.zig").stdoutPrint;

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

pub fn printAsciiLogo() anyerror!void {
    try stdoutPrint("{s}{s}{s}", .{
        colors.colorCode(colors.Color.Yellow),
        ascii_logo,
        colors.colorCode(colors.Color.Reset),
    });
}
