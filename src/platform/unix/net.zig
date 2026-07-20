//! Unix loopback TCP probe via the portable std.Io.net sockets.

const std = @import("std");

pub fn canConnectLoopback(io: std.Io, port: u16) bool {
    const addr = std.Io.net.IpAddress.parse("127.0.0.1", port) catch return false;
    var stream = addr.connect(io, .{ .mode = .stream }) catch return false;
    stream.close(io);
    return true;
}
