const std = @import("std");
const handleChunkSize = @import("./chunk_size.zig").handleChunkSize;
const Config = @import("../../commands/config/config.zig").Config;

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
