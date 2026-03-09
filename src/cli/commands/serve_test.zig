const std = @import("std");
const serve = @import("serve.zig");

test "deriveMimeType returns correct types" {
    try std.testing.expectEqualStrings("text/html; charset=utf-8", serve.deriveMimeType("report.html"));
    try std.testing.expectEqualStrings("application/json", serve.deriveMimeType("content.json"));
    try std.testing.expectEqualStrings("text/css", serve.deriveMimeType("style.css"));
    try std.testing.expectEqualStrings("application/javascript", serve.deriveMimeType("app.js"));
    try std.testing.expectEqualStrings("text/markdown", serve.deriveMimeType("report.md"));
    try std.testing.expectEqualStrings("application/octet-stream", serve.deriveMimeType("unknown.xyz"));
}

test "isPathSafe rejects traversal" {
    try std.testing.expect(!serve.isPathSafe("../etc/passwd"));
    try std.testing.expect(!serve.isPathSafe("/etc/passwd"));
    try std.testing.expect(!serve.isPathSafe("foo/../../etc"));
    try std.testing.expect(serve.isPathSafe("report.html"));
    try std.testing.expect(serve.isPathSafe("report-content.json"));
    try std.testing.expect(serve.isPathSafe("subdir/file.html"));
}
