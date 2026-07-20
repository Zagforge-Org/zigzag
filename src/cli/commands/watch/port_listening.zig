const std = @import("std");
const net = @import("../../../platform/net.zig");

/// Returns true if a TCP listener is actively accepting connections on `port`.
/// A successful loopback connect means something is listening; a refused connection
/// means the port is free. Used to find an open port for the dashboard server.
pub fn isPortListening(io: std.Io, port: u16) bool {
    return net.canConnectLoopback(io, port);
}
