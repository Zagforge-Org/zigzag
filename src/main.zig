const std = @import("std");
const config = @import("./cli/commands/config/config.zig");
const runner = @import("./cli/commands/runner.zig");
const watch = @import("./cli/commands/watch.zig");
const serve = @import("./cli/commands/serve.zig");
const CacheImpl = @import("cache/impl.zig").CacheImpl;
const printAsciiLogo = @import("./cli/handlers/logo.zig").printAsciiLogo;
const initHandler = @import("./cli/handlers/init.zig").handleInit;
const lg = @import("./cli/commands/logger.zig");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create list to hold command-line arguments
    var list: std.ArrayList([]const u8) = .empty;
    defer list.deinit(allocator);

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip(); // skip program name

    var param_count: usize = 0;
    var is_run_command = false;
    var is_serve_command = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "init")) {
            try initHandler(allocator, std.fs.cwd());
            return;
        }

        if (std.mem.eql(u8, arg, "run")) {
            is_run_command = true;
            continue; // "run" itself is not forwarded to the option parser
        }

        if (std.mem.eql(u8, arg, "serve")) {
            is_serve_command = true;
            continue; // "serve" itself is not forwarded to the option parser
        }

        if (std.mem.startsWith(u8, arg, "--")) {
            param_count += 1;
        } else {
            lg.printWarn("unknown argument: {s}", .{arg});
            return;
        }

        try list.append(allocator, arg);
    }

    // With no flags and no subcommand, just print usage
    if (param_count == 0 and !is_run_command and !is_serve_command) {
        try printAsciiLogo();
        return;
    }

    // Parse config: load zig.conf.json as base, then apply CLI args on top
    const result = config.Config.parseFromFile(list.items, allocator);
    switch (result) {
        config.ConfigParseResult.Success => |cfg| {
            var typedCfg: config.Config = cfg;
            defer typedCfg.deinit();

            // serve subcommand: start static file server from output dir
            if (is_serve_command) {
                const root_dir: []const u8 = if (typedCfg.output_dir) |d| d else "zigzag-reports";
                serve.execServe(.{
                    .root_dir = root_dir,
                    .port = typedCfg.serve_port,
                    .open_browser = typedCfg.open_browser,
                    .allocator = allocator,
                }) catch |err| {
                    lg.printError("serve error: {s}", .{@errorName(err)});
                };
                return;
            }

            // Only initialize cache and run if paths are configured and is_run_command is true
            if (typedCfg.paths.items.len > 0 and is_run_command) {
                // Create cache directory path (./.cache)
                const cache_path = try std.fs.path.join(allocator, &.{ ".", ".cache" });
                defer allocator.free(cache_path);

                // Initialize cache with configured threshold
                var cache = try CacheImpl.init(allocator, cache_path, typedCfg.small_threshold);
                defer cache.deinit();

                if (typedCfg.skip_cache) {
                    lg.printStep("Clearing cache: {s}", .{cache_path});
                    try cache.cleanup();
                    lg.printSuccess("Cache cleared", .{});
                }

                if (typedCfg.watch) {
                    watch.execWatch(&typedCfg, &cache, allocator) catch |err| {
                        lg.printError("watch error: {s}", .{@errorName(err)});
                    };
                } else {
                    _ = runner.exec(&typedCfg, &cache, allocator) catch |err| {
                        switch (err) {
                            error.ErrorNotFound => {
                                return;
                            },
                            else => {
                                lg.printError("error executing runner: {s}", .{@errorName(err)});
                            },
                        }
                    };
                }
            } else if (is_run_command) {
                lg.printWarn("no paths configured — add --path or set \"paths\" in zig.conf.json", .{});
            }
        },
        config.ConfigParseResult.MissingValue => |opt| {
            lg.printError("missing value for option: {s}", .{opt});
            return;
        },
        config.ConfigParseResult.UnknownOption => |opt| {
            lg.printError("unknown option: {s}", .{opt});
            return;
        },
        config.ConfigParseResult.Other => |err_name| {
            lg.printError("handler failed: {s}", .{err_name});
            return;
        },
    }
}
