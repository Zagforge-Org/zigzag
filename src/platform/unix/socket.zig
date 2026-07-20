//! Unix socket I/O: a plain read and a straight close.

const std = @import("std");

pub fn recv(handle: std.posix.socket_t, buf: []u8) !usize {
    return std.posix.read(handle, buf);
}

/// recv() bounded by a poll timeout so a silent peer cannot block the caller.
pub fn recvTimeout(handle: std.posix.socket_t, buf: []u8, timeout_ms: i32) !usize {
    var pfds = [1]std.posix.pollfd{.{ .fd = handle, .events = std.posix.POLL.IN, .revents = 0 }};
    const n_ready = std.posix.poll(&pfds, timeout_ms) catch return error.Timeout;
    if (n_ready == 0) return error.Timeout;
    return std.posix.read(handle, buf);
}

pub fn gracefulClose(io: std.Io, stream: std.Io.net.Stream) void {
    stream.close(io);
}
