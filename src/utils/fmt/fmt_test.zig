const std = @import("std");
const fmt_utils = @import("./fmt.zig");

test "fmtThousands inserts separators" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("0", fmt_utils.fmtThousands(&buf, 0));
    try std.testing.expectEqualStrings("999", fmt_utils.fmtThousands(&buf, 999));
    try std.testing.expectEqualStrings("1,000", fmt_utils.fmtThousands(&buf, 1_000));
    try std.testing.expectEqualStrings("1,234,567", fmt_utils.fmtThousands(&buf, 1_234_567));
}

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

test "fmtMilliseconds sub-ms returns < 1 ms" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("< 1 ms", fmt_utils.fmtMilliseconds(&buf, 0));
    try std.testing.expectEqualStrings("< 1 ms", fmt_utils.fmtMilliseconds(&buf, 500_000));
    try std.testing.expectEqualStrings("< 1 ms", fmt_utils.fmtMilliseconds(&buf, 999_999));
}

test "fmtMilliseconds ms range" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("1 ms", fmt_utils.fmtMilliseconds(&buf, 1_000_000));
    try std.testing.expectEqualStrings("42 ms", fmt_utils.fmtMilliseconds(&buf, 42_000_000));
    try std.testing.expectEqualStrings("1500 ms", fmt_utils.fmtMilliseconds(&buf, 1_500_000_000));
}

test "fmtElapsed sub-ms returns < 1ms" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("< 1ms", fmt_utils.fmtElapsed(&buf, 0));
    try std.testing.expectEqualStrings("< 1ms", fmt_utils.fmtElapsed(&buf, 500_000));
    try std.testing.expectEqualStrings("< 1ms", fmt_utils.fmtElapsed(&buf, 999_999));
}

test "fmtElapsed ms range" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("1ms", fmt_utils.fmtElapsed(&buf, 1_000_000));
    try std.testing.expectEqualStrings("42ms", fmt_utils.fmtElapsed(&buf, 42_000_000));
    try std.testing.expectEqualStrings("999ms", fmt_utils.fmtElapsed(&buf, 999_000_000));
}

test "fmtElapsed seconds range" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("1.00s", fmt_utils.fmtElapsed(&buf, 1_000_000_000));
    try std.testing.expectEqualStrings("1.50s", fmt_utils.fmtElapsed(&buf, 1_500_000_000));
    try std.testing.expectEqualStrings("60.00s", fmt_utils.fmtElapsed(&buf, 60_000_000_000));
}
