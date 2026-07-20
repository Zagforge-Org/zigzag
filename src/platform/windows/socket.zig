//! Windows socket I/O via raw Winsock: a recv() that bypasses ReadFile, and a
//! graceful close (shutdown + drain) so closesocket() does not send an RST: without
//! it the browser sees ERR_CONNECTION_RESET when unread data remains in the buffer.

const std = @import("std");

const ws2 = struct {
    extern "ws2_32" fn recv(s: std.posix.socket_t, buf: [*]u8, len: c_int, flags: c_int) callconv(.winapi) c_int;
    extern "ws2_32" fn shutdown(s: std.posix.socket_t, how: c_int) callconv(.winapi) c_int;
};

pub fn recv(handle: std.posix.socket_t, buf: []u8) !usize {
    if (buf.len == 0) return 0;
    const n = ws2.recv(handle, buf.ptr, @intCast(buf.len), 0);
    if (n < 0) return error.ConnectionResetByPeer;
    return @intCast(n);
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
