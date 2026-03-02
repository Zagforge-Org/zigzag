const std = @import("std");
const walk = @import("../../fs/walk.zig").Walk;
const walkerCallback = @import("../../walker/callback.zig").walkerCallback;
const Config = @import("config.zig").Config;
const FileContext = @import("../context.zig").FileContext;
const Pool = @import("../../workers/pool.zig").Pool;
const WaitGroup = @import("../../workers/wait_group.zig").WaitGroup;
const CacheImpl = @import("../../cache/impl.zig").CacheImpl;
const ProcessStats = @import("stats.zig").ProcessStats;
const JobEntry = @import("../../jobs/entry.zig").JobEntry;
const BinaryEntry = @import("../../jobs/entry.zig").BinaryEntry;
const WalkerCtx = @import("../../walker/context.zig").WalkerCtx;
const report = @import("report.zig");

/// Process a single directory path (one-shot mode)
fn processPath(
    cfg: *const Config,
    cache: ?*CacheImpl,
    path: []const u8,
    pool: *Pool,
    allocator: std.mem.Allocator,
) !void {
    if (path.len != 0) {
        std.log.info("Processing path: {s}", .{path});
    }

    var dir = std.fs.cwd().openDir(path, .{}) catch {
        return error.NotADirectory;
    };
    defer dir.close();

    const output_filename: []const u8 = if (cfg.output) |o| o else "report.md";
    const md_path = try std.fs.path.join(allocator, &.{ path, output_filename });
    defer allocator.free(md_path);

    var file_ctx = FileContext{
        .ignore_list = .{},
        .md = undefined,
        .md_mutex = undefined,
    };
    defer file_ctx.ignore_list.deinit(allocator);

    const owned_md_path = try allocator.dupe(u8, md_path);
    try file_ctx.ignore_list.append(allocator, owned_md_path);

    if (cfg.ignore_patterns.len != 0) {
        var it = std.mem.splitSequence(u8, cfg.ignore_patterns, ",");
        while (it.next()) |pattern| {
            const owned_pattern = try allocator.dupe(u8, pattern);
            try file_ctx.ignore_list.append(allocator, owned_pattern);
        }
    }

    var wg = WaitGroup.init();
    var stats = ProcessStats.init();

    var file_entries = std.StringHashMap(JobEntry).init(allocator);
    defer {
        var it = file_entries.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.value_ptr.path);
            allocator.free(entry.value_ptr.content);
            allocator.free(entry.value_ptr.extension);
        }
        file_entries.deinit();
    }

    var binary_entries = std.StringHashMap(BinaryEntry).init(allocator);
    defer {
        var it = binary_entries.iterator();
        while (it.next()) |entry| {
            std.heap.page_allocator.free(entry.value_ptr.path);
            std.heap.page_allocator.free(entry.value_ptr.extension);
        }
        binary_entries.deinit();
    }

    var entries_mutex = std.Thread.Mutex{};

    var walker_ctx = WalkerCtx{
        .pool = pool,
        .wg = &wg,
        .file_ctx = &file_ctx,
        .cache = cache,
        .stats = &stats,
        .file_entries = &file_entries,
        .binary_entries = &binary_entries,
        .entries_mutex = &entries_mutex,
        .allocator = allocator,
    };

    const walker = try walk.init(allocator);
    const walk_ctx: ?*FileContext = @ptrCast(@alignCast(&walker_ctx));

    try walker.walkDir(path, walkerCallback, walk_ctx);
    wg.wait();

    try report.writeReport(&file_entries, md_path, path, cfg, allocator);

    if (cfg.json_output) {
        const json_path = try report.deriveJsonPath(allocator, md_path);
        defer allocator.free(json_path);
        try report.writeJsonReport(&file_entries, &binary_entries, json_path, path, cfg, allocator);
    }

    std.log.info("=== Summary for {s} ===", .{path});
    stats.printSummary();
}

/// Executes the runner command for all configured paths.
pub fn exec(cfg: *const Config, cache: ?*CacheImpl) !void {
    if (cfg.paths.items.len == 0) return;

    const allocator = std.heap.page_allocator;

    var pool = Pool{};
    try pool.init(.{
        .allocator = allocator,
        .n_jobs = cfg.n_threads,
    });
    defer pool.deinit();

    std.log.info("Processing {d} path(s)...", .{cfg.paths.items.len});

    for (cfg.paths.items) |path| {
        processPath(cfg, cache, path, &pool, allocator) catch |err| {
            switch (err) {
                error.NotADirectory => {
                    std.log.err("Path '{s}' is not a directory", .{path});
                    return error.ErrorNotFound;
                },
                else => {
                    std.log.err("Unexpected error: {s}", .{@errorName(err)});
                },
            }
        };
    }

    std.log.info("All paths processed successfully!", .{});
}
