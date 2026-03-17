const std = @import("std");
const colors = @import("./colors.zig");

test "colorCode Reset returns reset escape" {
    try std.testing.expectEqualStrings("\x1b[0m", colors.colorCode(.Reset));
}

test "colorCode BrightCyan returns correct escape" {
    try std.testing.expectEqualStrings("\x1b[96m", colors.colorCode(.BrightCyan));
}

test "colorCode BrightGreen returns correct escape" {
    try std.testing.expectEqualStrings("\x1b[92m", colors.colorCode(.BrightGreen));
}

test "colorCode BrightRed returns correct escape" {
    try std.testing.expectEqualStrings("\x1b[91m", colors.colorCode(.BrightRed));
}

test "colorCode BrightYellow returns correct escape" {
    try std.testing.expectEqualStrings("\x1b[93m", colors.colorCode(.BrightYellow));
}

test "colorCode all variants return non-empty strings" {
    const all = [_]colors.Color{
        .Black, .Red, .Green, .Yellow, .Blue, .Magenta, .Cyan, .White,
        .BrightBlack, .BrightRed, .BrightGreen, .BrightYellow,
        .BrightBlue, .BrightMagenta, .BrightCyan, .BrightWhite, .Reset,
    };
    for (all) |c| {
        try std.testing.expect(colors.colorCode(c).len > 0);
    }
}
