const std = @import("std");

const SYSCTL_CPU_NAME = "machdep.cpu.brand_string";

const Sysctl = struct {
    extern "c" fn sysctlbyname(
        name: [*:0]const u8,
        oldp: ?*anyopaque,
        oldlenp: ?*usize,
        newp: ?*anyopaque,
        newlen: usize,
    ) c_int;
};

pub fn getCpuName(_: std.Io, buf: []u8) []const u8 {
    var len = buf.len;

    if (Sysctl.sysctlbyname(
        SYSCTL_CPU_NAME,
        buf.ptr,
        &len,
        null,
        0,
    ) != 0) {
        return "unknown";
    }

    return trimNull(buf, len);
}

fn trimNull(buf: []u8, len: usize) []const u8 {
    const end = if (len > 0 and buf[len - 1] == 0)
        len - 1
    else
        len;

    return buf[0..end];
}
