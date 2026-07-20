const std = @import("std");

const HKEY = *anyopaque;

const HKEY_LOCAL_MACHINE: HKEY = @ptrFromInt(0x80000002);
const KEY_READ: u32 = 0x20019;

const CPU_REG_PATH = "HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0";
const CPU_REG_VALUE = "ProcessorNameString";

const advapi32 = struct {
    extern "advapi32" fn RegOpenKeyExA(
        hKey: HKEY,
        lpSubKey: [*:0]const u8,
        ulOptions: u32,
        samDesired: u32,
        phkResult: *HKEY,
    ) i32;

    extern "advapi32" fn RegQueryValueExA(
        hKey: HKEY,
        lpValueName: [*:0]const u8,
        lpReserved: ?*u32,
        lpType: ?*u32,
        lpData: ?[*]u8,
        lpcbData: ?*u32,
    ) i32;

    extern "advapi32" fn RegCloseKey(
        hKey: HKEY,
    ) i32;
};

pub fn getCpuName(_: std.Io, buf: []u8) []const u8 {
    var key: HKEY = undefined;

    if (advapi32.RegOpenKeyExA(
        HKEY_LOCAL_MACHINE,
        CPU_REG_PATH,
        0,
        KEY_READ,
        &key,
    ) != 0) {
        return "unknown";
    }

    defer _ = advapi32.RegCloseKey(key);

    var value_len: u32 = @intCast(buf.len);

    if (advapi32.RegQueryValueExA(
        key,
        CPU_REG_VALUE,
        null,
        null,
        buf.ptr,
        &value_len,
    ) != 0) {
        return "unknown";
    }

    return trimNull(buf, value_len);
}

fn trimNull(buf: []u8, len: u32) []const u8 {
    const size: usize = @intCast(len);

    return if (size > 0 and buf[size - 1] == 0)
        buf[0 .. size - 1]
    else
        buf[0..size];
}
