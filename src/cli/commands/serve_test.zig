const std = @import("std");
const serve = @import("serve.zig");
const isPortListening = @import("./watch/port_listening.zig").isPortListening;

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
    const addr = try std.Io.net.IpAddress.parse("127.0.0.1", 0);
    var listener = try addr.listen(std.testing.io, .{});
    const ephemeral_port = listener.socket.address.getPort();
    listener.deinit(std.testing.io);
    // Give the OS a moment to release the socket.
    std.Io.sleep(std.testing.io, .fromNanoseconds(10 * std.time.ns_per_ms), .awake) catch {};
    try std.testing.expect(!isPortListening(std.testing.io, ephemeral_port));
}

test "serve.isPortListening returns true for an actively listening port" {
    const addr = try std.Io.net.IpAddress.parse("127.0.0.1", 0);
    var listener = try addr.listen(std.testing.io, .{});
    defer listener.deinit(std.testing.io);
    const port = listener.socket.address.getPort();
    try std.testing.expect(isPortListening(std.testing.io, port));
}

test "serve.isPortListening detects port occupied even with SO_REUSEADDR on second bind" {
    // Regression: SO_REUSEADDR may allow a second bind() to succeed; the probe must
    // still report the port as occupied because the original listener is still active.
    const addr = try std.Io.net.IpAddress.parse("127.0.0.1", 0);
    var listener = try addr.listen(std.testing.io, .{});
    defer listener.deinit(std.testing.io);
    const port = listener.socket.address.getPort();

    // Attempt duplicate bind with SO_REUSEADDR — mirrors what SseServer.init does.
    const addr2 = try std.Io.net.IpAddress.parse("127.0.0.1", port);
    if (addr2.listen(std.testing.io, .{ .reuse_address = true })) |second| {
        var s = second;
        s.deinit(std.testing.io);
    } else |_| {}

    // The original listener is still up — probe must return true.
    try std.testing.expect(isPortListening(std.testing.io, port));
}
