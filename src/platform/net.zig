//! Loopback TCP connectivity probe, dispatched to the per-OS implementation.

const std = @import("std");
const builtin = @import("builtin");

/// Attempts a TCP connection to 127.0.0.1:`port`. Returns true when the connection
/// is accepted (something is listening) and false on refusal or any error.
pub fn canConnectLoopback(io: std.Io, port: u16) bool {
    return switch (comptime builtin.os.tag) {
        .windows => @import("windows/net.zig").canConnectLoopback(io, port),
        else => @import("unix/net.zig").canConnectLoopback(io, port),
    };
}
