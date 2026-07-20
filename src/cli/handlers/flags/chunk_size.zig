const std = @import("std");
const Config = @import("../../commands/config/Config.zig");

fn parseChunkSize(value: []const u8) !usize {
    const last = value[value.len - 1];

    const numeric: []const u8, const multiplier: usize = switch (last) {
        'k', 'K' => .{ value[0 .. value.len - 1], 1_000 },
        'm', 'M' => .{ value[0 .. value.len - 1], 1_000_000 },
        '0'...'9' => .{ value, 1 },
        else => return error.InvalidChunkSize,
    };

    const size = std.fmt.parseInt(usize, numeric, 10) catch return error.InvalidChunkSize;

    if (size == 0)
        return error.InvalidChunkSize;

    return std.math.mul(usize, size, multiplier) catch return error.InvalidChunkSize;
}

pub fn handleChunkSize(
    _: std.Io,
    cfg: *Config,
    allocator: std.mem.Allocator,
    value: ?[]const u8,
) anyerror!void {
    _ = allocator;

    const trimmed = std.mem.trim(u8, value orelse return, &std.ascii.whitespace);
    if (trimmed.len == 0)
        return;

    cfg.llm_chunk_size = try parseChunkSize(trimmed);
}
