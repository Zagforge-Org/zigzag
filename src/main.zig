const std = @import("std");
const config = @import("./cli/config.zig");
const runner = @import("./cli/runner.zig");
const FileCache = @import("./fs/cache.zig").FileCache;

fn processChunk(_: []const u8) !void {
    // Do nothing (or count bytes, hash, etc.)
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Create cache directory path (./.cache)
    const cachePath = try std.fs.path.join(allocator, &.{ ".", ".cache" });
    defer allocator.free(cachePath);

    // Initialize cache with 64KB threshold for small files
    // Small files use path-based caching, large files use hash-based caching
    var cache = try FileCache.init(allocator, cachePath, 64 * 1024);
    defer cache.deinit();

    var it = std.process.args();
    _ = it.next(); // Skip program name

    // Create list to hold command-line arguments
    var list = std.ArrayList([]const u8){};
    defer list.deinit(allocator);

    // Check for --clear-cache flag
    var should_clear_cache = false;
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--clear-cache")) {
            should_clear_cache = true;
        } else {
            try list.append(allocator, arg);
        }
    }

    // Clear cache if requested
    if (should_clear_cache) {
        std.log.info("Clearing cache...", .{});
        try cache.cleanup();
        std.log.info("Cache cleared successfully", .{});
        if (list.items.len == 0) {
            return; // Just clear cache and exit
        }
    }

    // Parse config from remaining arguments
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

