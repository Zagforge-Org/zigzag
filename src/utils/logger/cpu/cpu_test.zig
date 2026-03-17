const std = @import("std");
const cpu = @import("./cpu.zig");

test "getCpuName returns a non-empty result" {
    var buf: [128]u8 = undefined;
    const name = cpu.getCpuName(&buf);
    try std.testing.expect(name.len > 0);
}

test "getCpuName result fits within buf" {
    var buf: [128]u8 = undefined;
    const name = cpu.getCpuName(&buf);
    try std.testing.expect(name.len <= buf.len);
}

test "getCpuName with minimal buf does not panic" {
    var buf: [4]u8 = undefined;
    _ = cpu.getCpuName(&buf);
}
