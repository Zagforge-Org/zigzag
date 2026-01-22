const std = @import("std");

const config = @import("./cli/config.zig");
const runner = @import("./cli/runner.zig");
const FileCache = @import("./fs/cache.zig").FileCache;

fn processChunk(_: []const u8) !void {
    // Do nothing (or count bytes, hash, etc.)
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Create cache directory path
    const cachePath = try std.fs.path.join(allocator, &.{ ".", ".cache" });
    defer allocator.free(cachePath);

    // Initialize cache with 64KB threshold for small files
    var cache = try FileCache.init(allocator, cachePath, 64 * 1024);
    defer cache.deinit();

    var it = std.process.args();
    _ = it.next(); // Skip program name

    var list = std.ArrayList([]const u8).init(allocator);
    defer list.deinit();

    while (it.next()) |arg| {
        try list.append(arg);
    }

    const result = config.Config.parse(list.items, allocator);
    switch (result) {
        config.ConfigParseResult.Success => |cfg| {
            // Pass cache to runner
            try runner.exec(&cfg, &cache);
        },
        config.ConfigParseResult.MissingValue => |opt| {
            std.log.err("ai-proj: missing value for option: {s}", .{opt});
            return;
        },
        config.ConfigParseResult.UnknownOption => |opt| {
            std.log.err("ai-proj: unknown option: {s}", .{opt});
            return;
        },
        config.ConfigParseResult.Other => |err_name| {
            std.log.err("ai-proj: handler failed: {s}", .{err_name});
            return;
        },
    }
}

