const std = @import("std");
const config = @import("./cli/commands/config.zig");
const runner = @import("./cli/commands/runner.zig");
const CacheImpl = @import("cache/impl.zig").CacheImpl;
const printAsciiLogo = @import("./cli/handlers.zig").printAsciiLogo;
const handleInit = @import("./cli/handlers.zig").handleInit;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Create list to hold command-line arguments
    var list: std.ArrayList([]const u8) = .empty;
    defer list.deinit(allocator);

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip(); // skip program name

    var param_count: usize = 0;
    var is_run_command = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "init")) {
            try handleInit(allocator, std.fs.cwd());
            return;
        }
        if (std.mem.eql(u8, arg, "run")) {
            is_run_command = true;
            continue; // "run" itself is not forwarded to the option parser
        }
        if (std.mem.startsWith(u8, arg, "--")) {
            param_count += 1;
        }
        try list.append(allocator, arg);
    }

    // With no flags and no "run" subcommand, just print usage
    if (param_count == 0 and !is_run_command) {
        try printAsciiLogo();
        return;
    }

    // Parse config: load zig.conf.json as base, then apply CLI args on top
    const result = config.Config.parseFromFile(list.items, allocator);
    switch (result) {
        config.ConfigParseResult.Success => |cfg| {
            var typedCfg: config.Config = cfg;
            defer typedCfg.deinit();

            // Only initialize cache and run if paths are configured
            if (typedCfg.paths.items.len > 0) {
                // Create cache directory path (./.cache)
                const cache_path = try std.fs.path.join(allocator, &.{ ".", ".cache" });
                defer allocator.free(cache_path);

                // Initialize cache with configured threshold
                var cache = try CacheImpl.init(allocator, cache_path, typedCfg.small_threshold);
                defer cache.deinit();

                if (typedCfg.skip_cache) {
                    std.log.info("Clearing cache directory: {s}", .{cache_path});
                    try cache.cleanup();
                    std.log.info("Cache cleared", .{});
                }

                if (typedCfg.watch) {
                    // Watch mode: run continuously, re-generating on each interval
                    std.log.info("Watch mode enabled (interval: {d}ms). Press Ctrl+C to stop.", .{typedCfg.watch_interval_ms});
                    while (true) {
                        _ = runner.exec(&typedCfg, &cache) catch |err| {
                            switch (err) {
                                error.ErrorNotFound => {},
                                else => std.log.err("zigzag: error during watch cycle: {s}", .{@errorName(err)}),
                            }
                        };
                        std.Thread.sleep(typedCfg.watch_interval_ms * std.time.ns_per_ms);
                    }
                } else {
                    _ = runner.exec(&typedCfg, &cache) catch |err| {
                        switch (err) {
                            error.ErrorNotFound => {
                                return;
                            },
                            else => {
                                std.log.err("zigzag: error executing runner: {s}", .{@errorName(err)});
                            },
                        }
                    };
                }
            } else if (is_run_command) {
                std.log.warn("zigzag: no paths configured. Add --path or set \"paths\" in zig.conf.json.", .{});
            }
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
