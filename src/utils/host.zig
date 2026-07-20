//! Host machine info: OS/arch labels and CPU-name lookup.

const builtin = @import("builtin");

/// Host OS name (e.g. "Linux", "macOS", "Windows").
pub fn getOs() []const u8 {
    return comptime switch (builtin.os.tag) {
        .linux => "Linux",
        .macos => "macOS",
        .windows => "Windows",
        else => @tagName(builtin.os.tag),
    };
}

/// Host CPU architecture name (e.g. "x86_64", "arm64").
pub fn getArch() []const u8 {
    return comptime switch (builtin.cpu.arch) {
        .x86_64 => "x86_64",
        .aarch64 => "arm64",
        else => @tagName(builtin.cpu.arch),
    };
}

pub const getCpuName = @import("../platform/cpu.zig").getCpuName;
