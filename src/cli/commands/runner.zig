const std = @import("std");
const fs = @import("../../fs/file.zig");
const walk = @import("../../fs/walk.zig").Walk;
const walkerCallback = @import("../../walker/callback.zig").walkerCallback;
const processFileJob = @import("../../jobs/process.zig").processFileJob;
const Config = @import("../commands/config.zig").Config;
const FileContext = @import("../context.zig").FileContext;
const Pool = @import("../../workers/pool.zig").Pool;
const WaitGroup = @import("../../workers/wait_group.zig").WaitGroup;
const CacheImpl = @import("../../cache/impl.zig").CacheImpl;
const ProcessStats = @import("stats.zig").ProcessStats;
const Job = @import("../../jobs/job.zig").Job;
const JobEntry = @import("../../jobs/entry.zig").JobEntry;
const WalkerCtx = @import("../../walker/context.zig").WalkerCtx;

/// Process a single directory path
fn processPath(
    cfg: *const Config,
    cache: *CacheImpl,
    path: []const u8,
    pool: *Pool,
    allocator: std.mem.Allocator,
) !void {
    std.log.info("Processing path: {s}", .{path});

    _ = std.fs.cwd().statFile(path) catch |err| {
        switch (err) {
            error.FileNotFound => {
                std.log.err("zig-zag: path not found: {s}", .{path});
            },
            else => {
                std.log.err("zig-zag: filesystem error for {s}: {s}", .{ path, @errorName(err) });
            },
        }
        return;
    };

    const md_path = try std.fs.path.join(allocator, &.{ path, "report.md" });
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
        }
        file_entries.deinit();
    }

    var entries_mutex = std.Thread.Mutex{};

    var walker_ctx = WalkerCtx{
        .pool = pool,
        .wg = &wg,
        .file_ctx = &file_ctx,
        .cache = cache,
        .stats = &stats,
        .file_entries = &file_entries,
        .entries_mutex = &entries_mutex,
        .allocator = allocator,
    };

    const walker = try walk.init(allocator);
    const walk_ctx: ?*FileContext = @ptrCast(@alignCast(&walker_ctx));

    try walker.walkDir(path, walkerCallback, walk_ctx);
    wg.wait();

    // Build report.md from all collected files
    std.log.info("Building report.md for {s}...", .{path});
    var md_file = try std.fs.cwd().createFile(md_path, .{ .truncate = true });
    defer md_file.close();

    // Write header with path information
    const header = try std.fmt.allocPrint(allocator, "# Report for: {s}\n\n", .{path});
    defer allocator.free(header);
    try md_file.writeAll(header);

    var it = file_entries.iterator();
    while (it.next()) |entry| {
        try md_file.writeAll(entry.value_ptr.content);
    }

    std.log.info("=== Summary for {s} ===", .{path});
    stats.printSummary();
}

/// Executes the runner command for all configured paths.
pub fn exec(cfg: *const Config, cache: *CacheImpl) !void {
    const allocator = std.heap.page_allocator;

    var pool = Pool{};
    try pool.init(.{
        .allocator = allocator,
        .n_jobs = cfg.n_threads,
    });
    defer pool.deinit();

    std.log.info("Processing {d} path(s)...", .{cfg.paths.items.len});

    for (cfg.paths.items) |path| {
        try processPath(cfg, cache, path, &pool, allocator);
    }

    std.log.info("All paths processed successfully!", .{});
}
