//! Socket I/O primitives that need OS-specific handling, dispatched per platform.

const std = @import("std");
const builtin = @import("builtin");

/// Read from a socket, bypassing ReadFile() on Windows. Drop-in for Stream.read:
/// returns bytes read, 0 on EOF, or an error.
pub fn recv(handle: std.posix.socket_t, buf: []u8) !usize {
    return switch (comptime builtin.os.tag) {
        .windows => @import("windows/socket.zig").recv(handle, buf),
        else => @import("unix/socket.zig").recv(handle, buf),
    };
}

/// Gracefully close a TCP connection, avoiding a RST on Windows.
pub fn gracefulClose(io: std.Io, stream: std.Io.net.Stream) void {
    switch (comptime builtin.os.tag) {
        .windows => @import("windows/socket.zig").gracefulClose(io, stream),
        else => @import("unix/socket.zig").gracefulClose(io, stream),
    }
}
