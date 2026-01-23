const std = @import("std");
const config = @import("./cli/commands/config.zig");
const runner = @import("./cli/commands/runner.zig");
const CacheImpl = @import("cache/impl.zig").CacheImpl;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Create cache directory path (./.cache)
    const cache_path = try std.fs.path.join(allocator, &.{ ".", ".cache" });
    defer allocator.free(cache_path);

    // Create list to hold command-line arguments
    var list = std.ArrayList([]const u8){};
    defer list.deinit(allocator);

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip(); // skip program name

    while (args.next()) |arg| {
        try list.append(allocator, arg);
    }

    // Parse config from arguments
    const result = config.Config.parse(list.items, allocator);
    switch (result) {
        config.ConfigParseResult.Success => |cfg| {
            var typedCfg: config.Config = cfg;

            // Initialize cache with 64KB threshold for small files
            // Small files use path-based caching, large files use hash-based caching
            var cache = try CacheImpl.init(allocator, cache_path, typedCfg.small_threshold);
            defer cache.deinit();

            if (typedCfg.skip_cache) {
                std.log.info("Clearing cache directory: {s}", .{cache_path});
                try cache.cleanup();
                std.log.info("Cache cleared", .{});
            }

            _ = runner.exec(&typedCfg, &cache) catch |err| {
                switch (err) {
                    error.ErrorNotFound => {
                        std.log.err("zig-zag: path not found", .{});
                    },
                    else => {
                        std.log.err("zig-zag: error executing runner", .{});
                    },
                }
            };
        },
        config.ConfigParseResult.MissingValue => |opt| {
            std.log.err("zig-zag: missing value for option: {s}", .{opt});
            return;
        },
        config.ConfigParseResult.UnknownOption => |opt| {
            std.log.err("zig-zag: unknown option: {s}", .{opt});
            return;
        },
        config.ConfigParseResult.Other => |err_name| {
            std.log.err("zig-zag: handler failed: {s}", .{err_name});
            return;
        },
    }
}
