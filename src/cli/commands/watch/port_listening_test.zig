const std = @import("std");
const isPortListening = @import("./port_listening.zig").isPortListening;
const Server = @import("./Server.zig");

// --- isPortListening tests ---

test "isPortListening returns false for an occupied port" {
    // Bind to an ephemeral port (0), record the assigned port, then release it.
    // After release the port should no longer have an active listener.
    const addr = try std.Io.net.IpAddress.parse("127.0.0.1", 0);
    var listener = try addr.listen(std.testing.io, .{});
    const ephemeral_port = listener.socket.address.getPort();
    listener.deinit(std.testing.io);
    // Give the OS a moment to release the socket before probing.
    std.Io.sleep(std.testing.io, .fromNanoseconds(10 * std.time.ns_per_ms), .awake) catch {};

    try std.testing.expect(!isPortListening(std.testing.io, ephemeral_port));
}

test "isPortListening returns true for an actively listening port" {
    const alloc = std.testing.allocator;
    // Server.init binds to an OS-assigned ephemeral port when port == 0.
    const srv = try Server.init(std.testing.io, 0, "/tmp", "report.html", alloc);
    defer srv.deinit();
    const actual_port = srv.listener.socket.address.getPort();
    try std.testing.expect(isPortListening(std.testing.io, actual_port));
}

test "isPortListening correctly detects two independent servers" {
    const alloc = std.testing.allocator;
    const srv1 = try Server.init(std.testing.io, 0, "/tmp", "report.html", alloc);
    defer srv1.deinit();
    const srv2 = try Server.init(std.testing.io, 0, "/tmp", "report.html", alloc);
    defer srv2.deinit();

    const p1 = srv1.listener.socket.address.getPort();
    const p2 = srv2.listener.socket.address.getPort();

    // Both ports must be distinct and both must be detected as listening.
    try std.testing.expect(p1 != p2);
    try std.testing.expect(isPortListening(std.testing.io, p1));
    try std.testing.expect(isPortListening(std.testing.io, p2));
}

test "port probe works even when SO_REUSEADDR would allow duplicate bind" {
    // This is the core regression test: verify that isPortListening detects an
    // occupied port even when a second bind() with SO_REUSEADDR would succeed.
    const alloc = std.testing.allocator;
    const srv = try Server.init(std.testing.io, 0, "/tmp", "report.html", alloc);
    defer srv.deinit();

    const occupied_port = srv.listener.socket.address.getPort();

    // Attempt a second bind with SO_REUSEADDR on the same port.
    const addr = try std.Io.net.IpAddress.parse("127.0.0.1", occupied_port);
    const maybe_second = addr.listen(std.testing.io, .{ .reuse_address = true });
    if (maybe_second) |second_srv| {
        // On some kernels SO_REUSEADDR allows this bind — exactly the bug we fix.
        // isPortListening must still detect the port as occupied.
        var s = second_srv;
        s.deinit(std.testing.io);
    } else |_| {}

    // Regardless of whether the duplicate bind succeeded or not, the original
    // server is still listening, so the probe must return true.
    try std.testing.expect(isPortListening(std.testing.io, occupied_port));
}

test "port selection skips an occupied port and binds to next free port" {
    const alloc = std.testing.allocator;

    // Occupy a port via Server.
    const occupier = try Server.init(std.testing.io, 0, "/tmp", "report.html", alloc);
    defer occupier.deinit();
    const occupied_port = occupier.listener.socket.address.getPort();

    // Simulate the retry loop: occupied_port is taken, occupied_port+1 should be free.
    // We bound occupied_port to an ephmeral high port, so occupied_port+1 is almost
    // certainly free — but we verify with isPortListening before asserting.
    const next_port: u16 = occupied_port +% 1;
    if (next_port == 0) return; // unlikely wraparound, skip

    // The occupied port must probe as listening.
    try std.testing.expect(isPortListening(std.testing.io, occupied_port));
    // The next port should be free (probe returns false).
    // If it's also occupied in the test environment, the assertion below is a no-op.
    if (!isPortListening(std.testing.io, next_port)) {
        // Verify we can actually bind to the next port.
        const addr = try std.Io.net.IpAddress.parse("127.0.0.1", next_port);
        var listener = try addr.listen(std.testing.io, .{ .reuse_address = true });
        defer listener.deinit(std.testing.io);
        // After binding, isPortListening must return true for that port too.
        try std.testing.expect(isPortListening(std.testing.io, next_port));
    }
}
