const std = @import("std");
const builtin = @import("builtin");

/// Returns the CPU model name into `buf`. Falls back to "unknown" on error.
pub fn getCpuName(buf: []u8) []const u8 {
    return switch (comptime builtin.os.tag) {
        .linux => getCpuNameLinux(buf),
        .macos => getCpuNameMacos(buf),
        .windows => getCpuNameWindows(buf),
        else => "unknown",
    };
}

fn getCpuNameLinux(buf: []u8) []const u8 {
    const f = std.fs.openFileAbsolute("/proc/cpuinfo", .{}) catch return "unknown";
    defer f.close();
    var tmp: [8192]u8 = undefined;
    const n = f.read(&tmp) catch return "unknown";
    const needle = "model name\t: ";
    const idx = std.mem.indexOf(u8, tmp[0..n], needle) orelse return "unknown";
    const start = idx + needle.len;
    const rest = tmp[start..n];
    const end = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
    const name = rest[0..@min(end, buf.len)];
    @memcpy(buf[0..name.len], name);
    return buf[0..name.len];
}

fn getCpuNameMacos(buf: []u8) []const u8 {
    const Sysctl = struct {
        extern "c" fn sysctlbyname(name: [*:0]const u8, oldp: ?*anyopaque, oldlenp: ?*usize, newp: ?*anyopaque, newlen: usize) c_int;
    };
    var size: usize = buf.len;
    const rc = Sysctl.sysctlbyname("machdep.cpu.brand_string", buf.ptr, &size, null, 0);
    if (rc != 0) return "unknown";
    if (size > 0 and buf[size - 1] == 0) size -= 1;
    return buf[0..size];
}

fn getCpuNameWindows(buf: []u8) []const u8 {
    const HKEY = *anyopaque;
    // HKEY_LOCAL_MACHINE = (HKEY)(LONG)0x80000002 — sign-extend the i32 to usize.
    const hklm_i32: i32 = @bitCast(@as(u32, 0x80000002));
    const HKEY_LOCAL_MACHINE: HKEY = @ptrFromInt(@as(usize, @bitCast(@as(isize, hklm_i32))));
    const KEY_READ: u32 = 0x20019;

    const advapi32 = struct {
        extern "advapi32" fn RegOpenKeyExA(hKey: HKEY, lpSubKey: [*:0]const u8, ulOptions: u32, samDesired: u32, phkResult: *HKEY) i32;
        extern "advapi32" fn RegQueryValueExA(hKey: HKEY, lpValueName: [*:0]const u8, lpReserved: ?*u32, lpType: ?*u32, lpData: ?[*]u8, lpcbData: ?*u32) i32;
        extern "advapi32" fn RegCloseKey(hKey: HKEY) i32;
    };

    var hkey: HKEY = undefined;
    if (advapi32.RegOpenKeyExA(
        HKEY_LOCAL_MACHINE,
        "HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0",
        0, KEY_READ, &hkey,
    ) != 0) return "unknown";
    defer _ = advapi32.RegCloseKey(hkey);

    var vtype: u32 = 0;
    var vlen: u32 = @intCast(buf.len);
    if (advapi32.RegQueryValueExA(hkey, "ProcessorNameString", null, &vtype, buf.ptr, &vlen) != 0) return "unknown";

    // Registry string includes a null terminator in the length.
    if (vlen > 0 and buf[vlen - 1] == 0) vlen -= 1;
    return buf[0..@intCast(vlen)];
}
