//! Windows socket I/O via raw Winsock: a recv() that bypasses ReadFile, and a
//! graceful close (shutdown + drain) so closesocket() does not send an RST: without
//! it the browser sees ERR_CONNECTION_RESET when unread data remains in the buffer.

const std = @import("std");

const ws2 = struct {
    const WSAPOLLFD = extern struct {
        fd: std.posix.socket_t,
        events: c_short,
        revents: c_short,
    };
    const POLLRDNORM: c_short = 0x0100;

    extern "ws2_32" fn recv(s: std.posix.socket_t, buf: [*]u8, len: c_int, flags: c_int) callconv(.winapi) c_int;
    extern "ws2_32" fn shutdown(s: std.posix.socket_t, how: c_int) callconv(.winapi) c_int;
    extern "ws2_32" fn WSAPoll(fdArray: [*]WSAPOLLFD, fds: c_ulong, timeout: c_int) callconv(.winapi) c_int;
};

pub fn recv(handle: std.posix.socket_t, buf: []u8) !usize {
    if (buf.len == 0) return 0;
    const n = ws2.recv(handle, buf.ptr, @intCast(buf.len), 0);
    if (n < 0) return error.ConnectionResetByPeer;
    return @intCast(n);
}

/// recv() bounded by a WSAPoll timeout so a silent peer cannot block the caller.
pub fn recvTimeout(handle: std.posix.socket_t, buf: []u8, timeout_ms: i32) !usize {
    var pfds = [1]ws2.WSAPOLLFD{.{ .fd = handle, .events = ws2.POLLRDNORM, .revents = 0 }};
    const n_ready = ws2.WSAPoll(&pfds, 1, timeout_ms);
    if (n_ready < 0) return error.Timeout;
    if (n_ready == 0) return error.Timeout;
    return recv(handle, buf);
}

pub fn gracefulClose(io: std.Io, stream: std.Io.net.Stream) void {
    _ = ws2.shutdown(stream.socket.handle, 1); // SD_SEND = 1 -> sends FIN
    // Drain remaining receive-buffer data so closesocket() does not RST.
    var drain: [1024]u8 = undefined;
    const drain_ptr: [*]u8 = @ptrCast(&drain);
    var drained: usize = 0;
    while (drained < 64 * 1024) {
        const n = ws2.recv(stream.socket.handle, drain_ptr, @intCast(drain.len), 0);
        if (n <= 0) break; // 0 = peer closed, negative = error (e.g. WSAECONNRESET)
        drained += @intCast(n);
    }
    stream.close(io);
}
