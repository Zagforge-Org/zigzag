const std = @import("std");
const rt = @import("../../../runtime.zig");

/// Returns true if a TCP listener is actively accepting connections on the given port.
/// `std.net` and the raw `std.posix` socket calls were removed in Zig 0.16.0, so this
/// probes via the new `std.Io.net` interface: a successful connect to 127.0.0.1:<port>
/// means something is listening; `ConnectionRefused` means the port is free.
pub fn isPortListening(port: u16) bool {
    const addr = std.Io.net.IpAddress.parse("127.0.0.1", port) catch return false;
    var stream = addr.connect(rt.io(), .{ .mode = .stream }) catch return false;
    stream.close(rt.io());
    return true;
}
