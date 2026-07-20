const std = @import("std");
const host = @import("./host.zig");

test "getOs returns a non-empty label" {
    try std.testing.expect(host.getOs().len > 0);
}

test "getArch returns a non-empty label" {
    try std.testing.expect(host.getArch().len > 0);
}

test "getCpuName returns a result within buf" {
    var buf: [128]u8 = undefined;
    const name = host.getCpuName(std.testing.io, &buf);
    try std.testing.expect(name.len > 0);
    try std.testing.expect(name.len <= buf.len);
}

test "getCpuName with minimal buf does not panic" {
    var buf: [4]u8 = undefined;
    _ = host.getCpuName(std.testing.io, &buf);
}
