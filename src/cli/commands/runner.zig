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
const watcher_mod = @import("../../fs/watcher.zig");
const Watcher = watcher_mod.Watcher;
const WatchEvent = watcher_mod.WatchEvent;

/// Write a single file entry to the report with metadata
fn writeFileEntry(
    md_file: *std.fs.File,
    entry: *const JobEntry,
    allocator: std.mem.Allocator,
    timezone_offset: ?i64,
) !void {
    const size_str = try entry.formatSize(allocator);
    defer allocator.free(size_str);

    const mtime_str = try entry.formatMtime(allocator, timezone_offset);
    defer allocator.free(mtime_str);

    const lang = entry.getLanguage();

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

    const code_fence_start = if (lang.len > 0)
        try std.fmt.allocPrint(allocator, "```{s}\n", .{lang})
    else
        try allocator.dupe(u8, "```\n");
    defer allocator.free(code_fence_start);

    try md_file.writeAll(code_fence_start);
    try md_file.writeAll(entry.content);

    if (entry.content.len > 0 and entry.content[entry.content.len - 1] != '\n') {
        try md_file.writeAll("\n");
    }

    try md_file.writeAll("```\n\n");
}

/// Serialize the in-memory entries map to report.md.
/// Called both from one-shot mode and watch mode.
fn writeReport(
    file_entries: *const std.StringHashMap(JobEntry),
    md_path: []const u8,
    root_path: []const u8,
    cfg: *const Config,
    allocator: std.mem.Allocator,
) !void {
    const output_filename = std.fs.path.basename(md_path);
    std.log.info("Building {s} for {s}...", .{ output_filename, root_path });

    var md_file = try std.fs.cwd().createFile(md_path, .{ .truncate = true });
    defer md_file.close();

    // Header with current timestamp
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
            root_path,
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

    // Table of contents
    try md_file.writeAll("## Table of Contents\n\n");

    var toc_list: std.ArrayList([]const u8) = .empty;
    defer {
        for (toc_list.items) |item| allocator.free(item);
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

    std.mem.sort([]const u8, toc_list.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    for (toc_list.items) |toc_entry| try md_file.writeAll(toc_entry);
    try md_file.writeAll("\n---\n\n");

    // Sorted file entries
    var sorted_entries: std.ArrayList(JobEntry) = .empty;
    defer sorted_entries.deinit(allocator);

    it = file_entries.iterator();
    while (it.next()) |entry| try sorted_entries.append(allocator, entry.value_ptr.*);

    std.mem.sort(JobEntry, sorted_entries.items, {}, struct {
        fn lessThan(_: void, a: JobEntry, b: JobEntry) bool {
            return std.mem.lessThan(u8, a.path, b.path);
        }
    }.lessThan);

    for (sorted_entries.items) |*entry| {
        try writeFileEntry(&md_file, entry, allocator, cfg.timezone_offset);
    }
}

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

    try writeReport(&file_entries, md_path, path, cfg, allocator);

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

// ============================================================
// Watch mode: event-driven, incremental in-memory updates
// ============================================================

/// Per-path persistent state for watch mode.
/// Heap-allocated so that entries_mutex has a stable address for thread pool jobs.
const PathWatchState = struct {
    root_path: []const u8,
    md_path: []const u8,
    file_entries: std.StringHashMap(JobEntry),
    entries_mutex: std.Thread.Mutex,
    file_ctx: FileContext,
    allocator: std.mem.Allocator,

    /// Run initial full directory scan and return heap-allocated state.
    fn init(
        cfg: *const Config,
        cache: ?*CacheImpl,
        path: []const u8,
        pool: *Pool,
        allocator: std.mem.Allocator,
    ) !*PathWatchState {
        var dir = std.fs.cwd().openDir(path, .{}) catch return error.NotADirectory;
        dir.close();

        const output_filename: []const u8 = if (cfg.output) |o| o else "report.md";
        const md_path = try std.fs.path.join(allocator, &.{ path, output_filename });
        errdefer allocator.free(md_path);

        const self = try allocator.create(PathWatchState);
        self.* = .{
            .root_path = try allocator.dupe(u8, path),
            .md_path = md_path,
            .file_entries = std.StringHashMap(JobEntry).init(allocator),
            .entries_mutex = .{},
            .file_ctx = .{
                .ignore_list = .{},
                .md = undefined,
                .md_mutex = undefined,
            },
            .allocator = allocator,
        };

        // Build ignore list (report.md + user patterns)
        const owned_md = try allocator.dupe(u8, md_path);
        try self.file_ctx.ignore_list.append(allocator, owned_md);

        if (cfg.ignore_patterns.len != 0) {
            var it = std.mem.splitSequence(u8, cfg.ignore_patterns, ",");
            while (it.next()) |pattern| {
                const owned = try allocator.dupe(u8, pattern);
                try self.file_ctx.ignore_list.append(allocator, owned);
            }
        }

        // Run initial full scan via thread pool
        var wg = WaitGroup.init();
        var stats = ProcessStats.init();
        var walker_ctx = WalkerCtx{
            .pool = pool,
            .wg = &wg,
            .file_ctx = &self.file_ctx,
            .cache = cache,
            .stats = &stats,
            .file_entries = &self.file_entries,
            .entries_mutex = &self.entries_mutex,
            .allocator = allocator,
        };

        const walker = try walk.init(allocator);
        const walk_ctx: ?*FileContext = @ptrCast(@alignCast(&walker_ctx));
        try walker.walkDir(path, walkerCallback, walk_ctx);
        wg.wait();

        std.log.info("=== Initial scan for {s} ===", .{path});
        stats.printSummary();

        return self;
    }

    fn deinit(self: *PathWatchState) void {
        const alloc = self.allocator;
        alloc.free(self.root_path);
        alloc.free(self.md_path);

        // processFileJob uses page_allocator internally for entry content/path slices
        var it = self.file_entries.iterator();
        while (it.next()) |entry| {
            std.heap.page_allocator.free(entry.value_ptr.path);
            std.heap.page_allocator.free(entry.value_ptr.content);
            std.heap.page_allocator.free(entry.value_ptr.extension);
        }
        self.file_entries.deinit();

        for (self.file_ctx.ignore_list.items) |item| alloc.free(item);
        self.file_ctx.ignore_list.deinit(alloc);

        alloc.destroy(self);
    }

    /// Re-process a single changed file and update the in-memory map.
    fn updateFile(self: *PathWatchState, file_path: []const u8, cache: ?*CacheImpl, pool: *Pool) !void {
        // Remove stale entry (free its owned slices) before re-processing
        self.entries_mutex.lock();
        if (self.file_entries.fetchRemove(file_path)) |kv| {
            std.heap.page_allocator.free(kv.value.path);
            std.heap.page_allocator.free(kv.value.content);
            std.heap.page_allocator.free(kv.value.extension);
        }
        self.entries_mutex.unlock();

        // Dispatch to thread pool (processFileJob frees path_copy via Job.deinit)
        const path_copy = try self.allocator.dupe(u8, file_path);
        var stats = ProcessStats.init();
        const job = Job{
            .path = path_copy,
            .file_ctx = &self.file_ctx,
            .cache = cache,
            .stats = &stats,
            .file_entries = &self.file_entries,
            .entries_mutex = &self.entries_mutex,
            .allocator = self.allocator,
        };

        var wg = WaitGroup.init();
        try pool.spawnWg(&wg, processFileJob, .{job});
        wg.wait();
    }

    /// Remove a deleted file's entry from the in-memory map.
    fn removeFile(self: *PathWatchState, file_path: []const u8) void {
        self.entries_mutex.lock();
        defer self.entries_mutex.unlock();
        if (self.file_entries.fetchRemove(file_path)) |kv| {
            std.heap.page_allocator.free(kv.value.path);
            std.heap.page_allocator.free(kv.value.content);
            std.heap.page_allocator.free(kv.value.extension);
        }
    }
};

/// Event-driven watch mode: uses OS filesystem events (inotify/kqueue/ReadDirectoryChangesW)
/// for incremental updates. Keeps all file content in memory; only re-reads changed files.
pub fn execWatch(cfg: *const Config, cache: ?*CacheImpl) !void {
    if (cfg.paths.items.len == 0) return;

    const allocator = std.heap.page_allocator;
    const output_filename: []const u8 = if (cfg.output) |o| o else "report.md";

    var pool = Pool{};
    try pool.init(.{ .allocator = allocator, .n_jobs = cfg.n_threads });
    defer pool.deinit();

    // --- Initial full scan for each configured path ---
    var states: std.ArrayList(*PathWatchState) = .empty;
    defer {
        for (states.items) |s| s.deinit();
        states.deinit(allocator);
    }

    for (cfg.paths.items) |path| {
        const state = PathWatchState.init(cfg, cache, path, &pool, allocator) catch |err| {
            switch (err) {
                error.NotADirectory => std.log.err("Path '{s}' is not a directory", .{path}),
                else => std.log.err("Failed to init watch state for '{s}': {s}", .{ path, @errorName(err) }),
            }
            continue;
        };
        try states.append(allocator, state);

        writeReport(&state.file_entries, state.md_path, state.root_path, cfg, allocator) catch |err| {
            std.log.err("Failed to write initial report for '{s}': {s}", .{ state.root_path, @errorName(err) });
        };
    }

    if (states.items.len == 0) return;

    // --- Set up OS-level filesystem watcher ---
    var watcher = try Watcher.init(allocator);
    defer watcher.deinit();

    for (states.items) |state| {
        watcher.watchDir(state.root_path) catch |err| {
            std.log.err("Failed to watch '{s}': {s}", .{ state.root_path, @errorName(err) });
        };
    }

    std.log.info("Watching {d} path(s) for changes. Press Ctrl+C to stop.", .{states.items.len});

    // --- Event loop with debounce ---
    var events: std.ArrayList(WatchEvent) = .empty;
    defer events.deinit(allocator);

    var dirty = false;
    // Debounce: wait for a 50ms quiet window after last event before writing
    const DEBOUNCE_MS: i32 = 50;

    while (true) {
        events.clearRetainingCapacity();

        // Block indefinitely when idle; drain quickly when events are pending
        const timeout: i32 = if (dirty) DEBOUNCE_MS else -1;
        const n = watcher.poll(&events, timeout) catch |err| {
            std.log.err("Watcher poll error: {s}", .{@errorName(err)});
            continue;
        };

        if (n > 0) {
            for (events.items) |event| {
                defer allocator.free(event.path);

                // Ignore .cache directory and the output report to avoid cycles
                if (std.mem.indexOf(u8, event.path, ".cache") != null) continue;
                if (std.mem.endsWith(u8, event.path, output_filename)) continue;

                // Find the PathWatchState that owns this path
                for (states.items) |state| {
                    if (!std.mem.startsWith(u8, event.path, state.root_path)) continue;

                    switch (event.kind) {
                        .created, .modified => {
                            state.updateFile(event.path, cache, &pool) catch |err| {
                                std.log.err("Failed to process {s}: {s}", .{ event.path, @errorName(err) });
                            };
                        },
                        .deleted => state.removeFile(event.path),
                    }
                    dirty = true;
                    break;
                }
            }
        } else if (dirty) {
            // Quiet period elapsed — write all reports from in-memory state
            for (states.items) |state| {
                writeReport(&state.file_entries, state.md_path, state.root_path, cfg, allocator) catch |err| {
                    std.log.err("Failed to write report for '{s}': {s}", .{ state.root_path, @errorName(err) });
                };
            }
            dirty = false;
        }
    }
}
