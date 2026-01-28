const std = @import("std");
const config = @import("./cli/commands/config.zig");
const runner = @import("./cli/commands/runner.zig");
const CacheImpl = @import("cache/impl.zig").CacheImpl;
const printAsciiLogo = @import("./cli/handlers.zig").printAsciiLogo;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Create list to hold command-line arguments
    var list: std.ArrayList([]const u8) = .empty;
    defer list.deinit(allocator);

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip(); // skip program name

    var param_count: usize = 0;
    while (args.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--")) {
            param_count += 1;
        }

        try list.append(allocator, arg);
    }

    if (param_count == 0) {
        // Print CLI and usage information
        try printAsciiLogo();
        return;
    }

    // Create cache directory path (./.cache)
    const cache_path = try std.fs.path.join(allocator, &.{ ".", ".cache" });
    defer allocator.free(cache_path);

    // Parse config from arguments
    const result = config.Config.parse(list.items, allocator);

    switch (result) {
        config.ConfigParseResult.Success => |cfg| {
            var typedCfg: config.Config = cfg;
            defer typedCfg.deinit();

            // Initialize cache with configured threshold
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
                        std.log.err("zigzag: path not found", .{});
                    },
                    else => {
                        std.log.err("zigzag: error executing runner: {s}", .{@errorName(err)});
                    },
                }
            };
        },
        config.ConfigParseResult.MissingValue => |opt| {
            std.log.err("zigzag: missing value for option: {s}", .{opt});
            return;
        },
        config.ConfigParseResult.UnknownOption => |opt| {
            std.log.err("zigzag: unknown option: {s}", .{opt});
            return;
        },
        config.ConfigParseResult.Other => |err_name| {
            std.log.err("zigzag: handler failed: {s}", .{err_name});
            return;
        },
    }
}
