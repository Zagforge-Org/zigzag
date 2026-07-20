//! Unix loopback TCP probe: a raw libc connect bounded by SO_SNDTIMEO.
//!
//! std.Io.net's connect timeout is not yet implemented for the posix backend,
//! and an unbounded connect() hangs through the kernel's full SYN-retry cycle
//! (~2 min) when the SYN is silently dropped; observed with the WSL2 loopback
//! relay for unbound ports. SO_SNDTIMEO bounds connect() on Linux and the BSDs.

const std = @import("std");
const posix = std.posix;

const CONNECT_TIMEOUT_US = 250_000;

const c = struct {
    extern "c" fn socket(domain: c_uint, sock_type: c_uint, protocol: c_uint) c_int;
    extern "c" fn connect(fd: c_int, addr: *const anyopaque, len: c_uint) c_int;
    extern "c" fn setsockopt(fd: c_int, level: c_int, optname: c_int, optval: *const anyopaque, optlen: c_uint) c_int;
    extern "c" fn close(fd: c_int) c_int;
};

pub fn canConnectLoopback(io: std.Io, port: u16) bool {
    _ = io;
    const fd = c.socket(posix.AF.INET, posix.SOCK.STREAM, 0);
    if (fd < 0) return false;
    defer _ = c.close(fd);

    const timeout = posix.timeval{ .sec = 0, .usec = CONNECT_TIMEOUT_US };
    _ = c.setsockopt(fd, posix.SOL.SOCKET, posix.SO.SNDTIMEO, &timeout, @sizeOf(posix.timeval));

    const sa = posix.sockaddr.in{
        .port = std.mem.nativeToBig(u16, port),
        .addr = std.mem.nativeToBig(u32, 0x7F000001), // 127.0.0.1
    };
    return c.connect(fd, &sa, @sizeOf(posix.sockaddr.in)) == 0;
}
