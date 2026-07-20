//! Unix socket I/O: a plain read and a straight close.

const std = @import("std");

pub fn recv(handle: std.posix.socket_t, buf: []u8) !usize {
    return std.posix.read(handle, buf);
}

pub fn gracefulClose(io: std.Io, stream: std.Io.net.Stream) void {
    stream.close(io);
}
