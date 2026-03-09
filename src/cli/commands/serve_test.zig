const std = @import("std");
const serve = @import("serve.zig");
const isPortListening = @import("serve.zig").isPortListening;

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

// --- port probe tests ---

test "serve.isPortListening returns false for a released port" {
    const addr = try std.net.Address.parseIp("127.0.0.1", 0);
    var listener = try addr.listen(.{});
    const ephemeral_port = listener.listen_address.getPort();
    listener.deinit();
    // Give the OS a moment to release the socket.
    std.Thread.sleep(10 * std.time.ns_per_ms);
    try std.testing.expect(!isPortListening(ephemeral_port));
}

test "serve.isPortListening returns true for an actively listening port" {
    const addr = try std.net.Address.parseIp("127.0.0.1", 0);
    var listener = try addr.listen(.{});
    defer listener.deinit();
    const port = listener.listen_address.getPort();
    try std.testing.expect(isPortListening(port));
}

test "serve.isPortListening detects port occupied even with SO_REUSEADDR on second bind" {
    // Regression: SO_REUSEADDR may allow a second bind() to succeed; the probe must
    // still report the port as occupied because the original listener is still active.
    const addr = try std.net.Address.parseIp("127.0.0.1", 0);
    var listener = try addr.listen(.{});
    defer listener.deinit();
    const port = listener.listen_address.getPort();

    // Attempt duplicate bind with SO_REUSEADDR — mirrors what SseServer.init does.
    const addr2 = try std.net.Address.parseIp("127.0.0.1", port);
    if (addr2.listen(.{ .reuse_address = true })) |second| {
        var s = second;
        s.deinit();
    } else |_| {}

    // The original listener is still up — probe must return true.
    try std.testing.expect(isPortListening(port));
}
