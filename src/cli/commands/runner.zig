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

/// Write a single file entry to the report with metadata
fn writeFileEntry(
    md_file: *std.fs.File,
    entry: *const JobEntry,
    allocator: std.mem.Allocator,
    timezone_offset: ?i64,
) !void {
    // Format metadata
    const size_str = try entry.formatSize(allocator);
    defer allocator.free(size_str);

    const mtime_str = try entry.formatMtime(allocator, timezone_offset);
    defer allocator.free(mtime_str);

    const lang = entry.getLanguage();

    // Write file header with metadata
    const header = try std.fmt.allocPrint(
        allocator,
        "## File: `{s}`\n\n" ++
            "**Metadata:**\n" ++
            "- **Size:** {s}\n" ++
            "- **Language:** {s}\n" ++
            "- **Last Modified:** {s}\n\n",
        .{
            entry.path,
            size_str,
            if (lang.len > 0) lang else "unknown",
            mtime_str,
        },
    );
    defer allocator.free(header);

    try md_file.writeAll(header);

    // Write code block with language identifier
    const code_fence_start = if (lang.len > 0)
        try std.fmt.allocPrint(allocator, "```{s}\n", .{lang})
    else
        try allocator.dupe(u8, "```\n");
    defer allocator.free(code_fence_start);

    try md_file.writeAll(code_fence_start);
    try md_file.writeAll(entry.content);

    // Ensure content ends with newline before closing fence
    if (entry.content.len > 0 and entry.content[entry.content.len - 1] != '\n') {
        try md_file.writeAll("\n");
    }

    try md_file.writeAll("```\n\n");
}

/// Process a single directory path
fn processPath(
    cfg: *const Config,
    cache: *CacheImpl,
    path: []const u8,
    pool: *Pool,
    allocator: std.mem.Allocator,
) !void {
    std.log.info("Processing path: {s}", .{path});

    // _ = std.fs.cwd().statFile(path) catch |err| {
    //     switch (err) {
    //         error.FileNotFound => {
    //             std.log.err("zig-zag: path not found: {s}", .{path});
    //         },
    //         else => {
    //             std.log.err("zig-zag: filesystem error for {s}: {s}", .{ path, @errorName(err) });
    //         },
    //     }
    //     return;
    // };
    //
    var dir = std.fs.cwd().openDir(path, .{}) catch |err| {
        std.log.err("zig-zag: failed to open directory {s}: {s}", .{ path, @errorName(err) });
        return;
    };
    defer dir.close();

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
            allocator.free(entry.value_ptr.extension);
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

    // Get current time in the configured timezone
    const now = std.time.timestamp();
    const local_now = if (cfg.timezone_offset) |offset| now + offset else now;

    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(local_now) };
    const day_seconds = epoch_seconds.getDaySeconds();
    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    const header = try std.fmt.allocPrint(
        allocator,
        "# Code Report for: `{s}`\n\n" ++
            "Generated on: {d}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}\n\n" ++
            "---\n\n",
        .{
            path,
            year_day.year,
            month_day.month.numeric(),
            month_day.day_index + 1,
            day_seconds.getHoursIntoDay(),
            day_seconds.getMinutesIntoHour(),
            day_seconds.getSecondsIntoMinute(),
        },
    );
    defer allocator.free(header);
    try md_file.writeAll(header);

    // Write table of contents
    try md_file.writeAll("## Table of Contents\n\n");

    var toc_list: std.ArrayList([]const u8) = .empty;
    defer {
        for (toc_list.items) |item| {
            allocator.free(item);
        }
        toc_list.deinit(allocator);
    }

    var it = file_entries.iterator();
    while (it.next()) |entry| {
        const toc_entry = try std.fmt.allocPrint(allocator, "- [{s}](#{s})\n", .{
            entry.value_ptr.path,
            entry.value_ptr.path,
        });
        try toc_list.append(allocator, toc_entry);
    }

    // Sort TOC entries for consistent output
    std.mem.sort([]const u8, toc_list.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    for (toc_list.items) |toc_entry| {
        try md_file.writeAll(toc_entry);
    }

    try md_file.writeAll("\n---\n\n");

    // Write file entries with metadata
    var sorted_entries: std.ArrayList(JobEntry) = .empty;
    defer sorted_entries.deinit(allocator);

    it = file_entries.iterator();
    while (it.next()) |entry| {
        try sorted_entries.append(allocator, entry.value_ptr.*);
    }

    // Sort entries by path for consistent output
    std.mem.sort(JobEntry, sorted_entries.items, {}, struct {
        fn lessThan(_: void, a: JobEntry, b: JobEntry) bool {
            return std.mem.lessThan(u8, a.path, b.path);
        }
    }.lessThan);

    for (sorted_entries.items) |*entry| {
        try writeFileEntry(&md_file, entry, allocator, cfg.timezone_offset);
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
