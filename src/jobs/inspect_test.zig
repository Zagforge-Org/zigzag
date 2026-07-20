const std = @import("std");
const inspect = @import("inspect.zig");

const countLines = inspect.countLines;
const isBinaryFile = inspect.isBinaryFile;

test "countLines returns 0 for empty content" {
    try std.testing.expectEqual(@as(usize, 0), countLines(""));
}

test "countLines counts a single line with no trailing newline" {
    try std.testing.expectEqual(@as(usize, 1), countLines("hello"));
}

test "countLines counts a single line with trailing newline" {
    try std.testing.expectEqual(@as(usize, 1), countLines("hello\n"));
}

test "countLines counts multiple lines with trailing newline" {
    try std.testing.expectEqual(@as(usize, 3), countLines("a\nb\nc\n"));
}

test "countLines counts multiple lines without trailing newline" {
    try std.testing.expectEqual(@as(usize, 3), countLines("a\nb\nc"));
}

test "isBinaryFile detects known binary extensions" {
    try std.testing.expect(isBinaryFile("logo.png", ""));
    try std.testing.expect(isBinaryFile("archive.zip", ""));
    try std.testing.expect(isBinaryFile("binary.exe", ""));
    try std.testing.expect(isBinaryFile("lib.so", ""));
}

test "isBinaryFile extension check is case-insensitive" {
    try std.testing.expect(isBinaryFile("logo.PNG", ""));
    try std.testing.expect(isBinaryFile("font.TTF", ""));
}

test "isBinaryFile returns false for text extensions" {
    try std.testing.expect(!isBinaryFile("main.zig", "const x = 1;"));
    try std.testing.expect(!isBinaryFile("script.py", "print('hi')"));
    try std.testing.expect(!isBinaryFile("README.md", "# Hello"));
}

test "isBinaryFile detects null bytes in content" {
    const content = "text\x00more";
    try std.testing.expect(isBinaryFile("unknown", content));
}

test "isBinaryFile detects high ratio of non-printable chars" {
    // Build a buffer where >30% of first 512 bytes are non-printable (control chars, not \n/\r/\t)
    var buf: [100]u8 = undefined;
    // 40 non-printable control chars (0x01) + 60 printable 'A' = 40% non-printable
    for (buf[0..40]) |*b| b.* = 0x01;
    for (buf[40..]) |*b| b.* = 'A';
    try std.testing.expect(isBinaryFile("data", &buf));
}

test "isBinaryFile returns false for low ratio of non-printable chars" {
    var buf: [100]u8 = undefined;
    // 10 control chars + 90 printable = 10% non-printable, below 30% threshold
    for (buf[0..10]) |*b| b.* = 0x01;
    for (buf[10..]) |*b| b.* = 'A';
    try std.testing.expect(!isBinaryFile("data", &buf));
}

test "isBinaryFile only examines first 512 bytes" {
    // First 512 bytes are clean text; byte 513+ has null byte which should NOT be detected
    var buf: [600]u8 = undefined;
    for (buf[0..512]) |*b| b.* = 'A';
    buf[512] = 0x00; // null byte beyond the check window
    try std.testing.expect(!isBinaryFile("data", &buf));
}
