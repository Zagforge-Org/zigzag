const std = @import("std");
const builtin = @import("builtin");
const rt = @import("../../../runtime.zig");

/// Returns true if a TCP listener is actively listening to connections on a given port.
/// A successful connect means something is listening whereas a refused connection
/// means the port is free.
///
/// On Windows probing with raw Winsock rather than `std.Io.net.connect` is the latter
/// that maps a refused connection to `error.Unexpected`, and, in debug/test builds, dumps a
/// noisy NSTATUS stack trace before returning. A direct `connect` reports refusal
/// quetly.
pub fn isPortListening(port: u16) bool {
    if (comptime builtin.os.tag == .windows) {
        const ws2 = struct {
            const SOCKET = usize;
            const INVALID_SOCKET: SOCKET = ~@as(SOCKET, 0);
            const SOCKET_ERROR: c_int = -1;
            const AF_INET: c_int = 2;
            const SOCK_STREAM: c_int = 1;
            const IPPROTO_TCP: c_int = 6;

            const sockaddr_in = extern struct {
                family: u16 = @intCast(AF_INET),
                port: u16,
                addr: u32,
                zero: [8]u8 = [_]u8{0} ** 8,
            };

            extern "ws2_32" fn WSAStartup(wVersionRequested: u16, lpWSAData: *anyopaque) callconv(.winapi) c_int;
            extern "ws2_32" fn socket(af: c_int, socktype: c_int, protocol: c_int) callconv(.winapi) SOCKET;
            extern "ws2_32" fn connect(s: SOCKET, name: *const sockaddr_in, namelen: c_int) callconv(.winapi) c_int;
            extern "ws2_32" fn closesocket(s: SOCKET) callconv(.winapi) c_int;
        };

        var wsadata: [512]u8 align(@alignOf(usize)) = undefined;
        if (ws2.WSAStartup(0x0202, &wsadata) != 0) return false;

        const sock = ws2.socket(ws2.AF_INET, ws2.SOCK_STREAM, ws2.IPPROTO_TCP);
        if (sock == ws2.INVALID_SOCKET) return false;
        defer _ = ws2.closesocket(sock);

        const sa = ws2.sockaddr_in{
            .port = std.mem.nativeToBig(u16, port),
            .addr = std.mem.nativeToBig(u32, 0x7f000001), // 127.0.0.1
        };
        return ws2.connect(sock, &sa, @sizeOf(ws2.sockaddr_in)) != ws2.SOCKET_ERROR;
    }

    const addr = std.Io.net.IpAddress.parse("127.0.0.1", port) catch return false;
    var stream = addr.connect(rt.io(), .{ .mode = .stream }) catch return false;
    stream.close(rt.io());
    return true;
}
