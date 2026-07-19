//! Host CPU-name lookup, dispatched to the per-OS reader.

const std = @import("std");
const builtin = @import("builtin");

/// Returns the CPU model name into `buf`. Falls back to "unknown" on error or
/// unsupported platforms.
pub fn getCpuName(io: std.Io, buf: []u8) []const u8 {
    return switch (comptime builtin.os.tag) {
        .linux => @import("linux/cpu.zig").getCpuName(io, buf),
        .macos => @import("macos/cpu.zig").getCpuName(io, buf),
        .windows => @import("windows/cpu.zig").getCpuName(io, buf),
        else => "unknown",
    };
}
