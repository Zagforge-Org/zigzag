const std = @import("std");
const Config = @import("../../commands/config/config.zig").Config;

pub fn handleChunkSize(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    const raw = value orelse return;
    const trimmed = std.mem.trim(u8, raw, &std.ascii.whitespace);
    if (trimmed.len == 0) return;

    var multiplier: usize = 1;
    var numeric: []const u8 = trimmed;
    const last = trimmed[trimmed.len - 1];

    if (last == 'k' or last == 'K') {
        multiplier = 1_000;
        numeric = trimmed[0 .. trimmed.len - 1];
    } else if (last == 'm' or last == 'M') {
        multiplier = 1_000_000;
        numeric = trimmed[0 .. trimmed.len - 1];
    } else if (last >= '0' and last <= '9') {
        // bare integer — no suffix
    } else {
        return error.InvalidChunkSize;
    }

    const n = std.fmt.parseInt(usize, numeric, 10) catch return error.InvalidChunkSize;
    if (n == 0) return error.InvalidChunkSize;
    cfg.llm_chunk_size = std.math.mul(usize, n, multiplier) catch return error.InvalidChunkSize;
}
