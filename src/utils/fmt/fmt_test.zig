const std = @import("std");
const fmt_utils = @import("./fmt.zig");

test "fmtBytes zero returns em dash" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("—", fmt_utils.fmtBytes(&buf, 0, false));
}

test "fmtBytes zero with html flag still returns em dash" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("—", fmt_utils.fmtBytes(&buf, 0, true));
}

test "fmtBytes sub-KB" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("1 B", fmt_utils.fmtBytes(&buf, 1, false));
    try std.testing.expectEqualStrings("1023 B", fmt_utils.fmtBytes(&buf, 1_023, false));
}

test "fmtBytes KB boundary" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("1.0 KB", fmt_utils.fmtBytes(&buf, 1_024, false));
    try std.testing.expectEqualStrings("2.0 KB", fmt_utils.fmtBytes(&buf, 2_048, false));
}

test "fmtBytes MB boundary" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("1.0 MB", fmt_utils.fmtBytes(&buf, 1_048_576, false));
    try std.testing.expectEqualStrings("1.5 MB", fmt_utils.fmtBytes(&buf, 1_572_864, false));
}

test "fmtBytes html suffix" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("1.0 KB (w/ content)", fmt_utils.fmtBytes(&buf, 1_024, true));
}

test "fmtElapsed sub-ms returns < 1ms" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("< 1ms", fmt_utils.fmtElapsed(0, &buf));
    try std.testing.expectEqualStrings("< 1ms", fmt_utils.fmtElapsed(500_000, &buf));
    try std.testing.expectEqualStrings("< 1ms", fmt_utils.fmtElapsed(999_999, &buf));
}

test "fmtElapsed ms range" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("1ms", fmt_utils.fmtElapsed(1_000_000, &buf));
    try std.testing.expectEqualStrings("42ms", fmt_utils.fmtElapsed(42_000_000, &buf));
    try std.testing.expectEqualStrings("999ms", fmt_utils.fmtElapsed(999_000_000, &buf));
}

test "fmtElapsed seconds range" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("1.00s", fmt_utils.fmtElapsed(1_000_000_000, &buf));
    try std.testing.expectEqualStrings("1.50s", fmt_utils.fmtElapsed(1_500_000_000, &buf));
    try std.testing.expectEqualStrings("60.00s", fmt_utils.fmtElapsed(60_000_000_000, &buf));
}
