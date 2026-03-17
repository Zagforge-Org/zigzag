const std = @import("std");
const Config = @import("../commands/config/config.zig").Config;

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

test "handleChunkSize: bare integer" {
    var cfg = Config.default(std.testing.allocator);
    defer cfg.deinit();
    try handleChunkSize(&cfg, std.testing.allocator, "500000");
    try std.testing.expectEqual(@as(usize, 500_000), cfg.llm_chunk_size);
}

test "handleChunkSize: k suffix" {
    var cfg = Config.default(std.testing.allocator);
    defer cfg.deinit();
    try handleChunkSize(&cfg, std.testing.allocator, "500k");
    try std.testing.expectEqual(@as(usize, 500_000), cfg.llm_chunk_size);
}

test "handleChunkSize: K suffix" {
    var cfg = Config.default(std.testing.allocator);
    defer cfg.deinit();
    try handleChunkSize(&cfg, std.testing.allocator, "500K");
    try std.testing.expectEqual(@as(usize, 500_000), cfg.llm_chunk_size);
}

test "handleChunkSize: m suffix" {
    var cfg = Config.default(std.testing.allocator);
    defer cfg.deinit();
    try handleChunkSize(&cfg, std.testing.allocator, "2m");
    try std.testing.expectEqual(@as(usize, 2_000_000), cfg.llm_chunk_size);
}

test "handleChunkSize: M suffix" {
    var cfg = Config.default(std.testing.allocator);
    defer cfg.deinit();
    try handleChunkSize(&cfg, std.testing.allocator, "2M");
    try std.testing.expectEqual(@as(usize, 2_000_000), cfg.llm_chunk_size);
}

test "handleChunkSize: zero is error" {
    var cfg = Config.default(std.testing.allocator);
    defer cfg.deinit();
    try std.testing.expectError(error.InvalidChunkSize, handleChunkSize(&cfg, std.testing.allocator, "0"));
}

test "handleChunkSize: invalid suffix is error" {
    var cfg = Config.default(std.testing.allocator);
    defer cfg.deinit();
    try std.testing.expectError(error.InvalidChunkSize, handleChunkSize(&cfg, std.testing.allocator, "500x"));
}

test "handleChunkSize: null value is no-op" {
    var cfg = Config.default(std.testing.allocator);
    defer cfg.deinit();
    try handleChunkSize(&cfg, std.testing.allocator, null);
    try std.testing.expectEqual(@as(usize, 0), cfg.llm_chunk_size);
}
