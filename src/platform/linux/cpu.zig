const std = @import("std");

const CPUINFO_PATH = "/proc/cpuinfo";
const MODEL_NAME_PREFIX = "model name\t: ";
const READ_BUFFER_SIZE = 8192;

pub fn getCpuName(io: std.Io, buf: []u8) []const u8 {
    const file = std.Io.Dir.openFileAbsolute(io, CPUINFO_PATH, .{}) catch return "unknown";
    defer file.close(io);

    var tmp: [READ_BUFFER_SIZE]u8 = undefined;
    const len = file.readStreaming(io, &.{tmp[0..]}) catch return "unknown";

    const name = parseCpuName(tmp[0..len]) orelse return "unknown";

    const copy_len = @min(name.len, buf.len);
    @memcpy(buf[0..copy_len], name[0..copy_len]);

    return buf[0..copy_len];
}

fn parseCpuName(data: []const u8) ?[]const u8 {
    const idx = std.mem.indexOf(u8, data, MODEL_NAME_PREFIX) orelse return null;

    const start = idx + MODEL_NAME_PREFIX.len;
    const rest = data[start..];

    const end = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;

    return rest[0..end];
}
