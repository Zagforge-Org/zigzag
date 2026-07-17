const std = @import("std");
const posix = std.posix;

/// Returns true if TCP listener is actively accepting connections on the given port.
/// This performs non-blocking connection probe with 10ms timeout.
/// Significantly faster than standard blocking probe and avoids OS-specific `SO_REUSEADDR` inconsistencies.
/// May return false on extremely congested systems where a local handshake takes longer than 10ms.
pub fn isPortListening(port: u16) bool {
    // Directly build port and address from network byte order.
    const addr: posix.sockaddr.in = .{
        .family = posix.AF.INET,
        .port = std.mem.nativeToBig(u16, port),
        .addr = std.mem.nativeToBig(u32, 0x7f000001),
    };

    // Create non-blocking socket
    const socket = posix.socket(posix.AF.INET, posix.SOCK.STREAM | posix.SOCK.NONBLOCK, 0) catch return false;
    defer posix.close(socket);

    // Start connection attempt
    posix.connect(socket, @ptrCast(&addr), @sizeOf(posix.sockaddr.in)) catch |err| {
        if (err == error.ConnectionRefused) return false;
        if (err != error.WouldBlock) return false;
    };

    // Use poll to wait for socket to become writable
    var poll_fds = [1]posix.pollfd{.{
        .fd = socket,
        .events = posix.POLL.OUT,
        .revents = 0,
    }};

    // Poll every 10ms
    const ready_count = posix.poll(&poll_fds, 10) catch return false;

    if (ready_count > 0) {
        var socket_err: i32 = 0;
        // The new signature takes: (fd, level, optname, []u8)
        // It returns !void, as the length is now handled by the slice itself.
        posix.getsockopt(socket, posix.SOL.SOCKET, posix.SO.ERROR, std.mem.asBytes(&socket_err)) catch return false;

        return socket_err == 0;
    }

    return false;
}
