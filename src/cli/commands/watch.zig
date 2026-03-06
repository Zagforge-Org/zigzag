const std = @import("std");
const walk = @import("../../fs/walk.zig").Walk;
const walkerCallback = @import("../../walker/callback.zig").walkerCallback;
const processFileJob = @import("../../jobs/process.zig").processFileJob;
const Config = @import("config/config.zig").Config;
const FileContext = @import("../context.zig").FileContext;
const Pool = @import("../../workers/pool.zig").Pool;
const WaitGroup = @import("../../workers/wait_group.zig").WaitGroup;
const CacheImpl = @import("../../cache/impl.zig").CacheImpl;
const ProcessStats = @import("stats.zig").ProcessStats;
const Job = @import("../../jobs/job.zig").Job;
const JobEntry = @import("../../jobs/entry.zig").JobEntry;
const BinaryEntry = @import("../../jobs/entry.zig").BinaryEntry;
const WalkerCtx = @import("../../walker/context.zig").WalkerCtx;
const watcher_mod = @import("../../fs/watcher.zig");
const Watcher = watcher_mod.Watcher;
const WatchEvent = watcher_mod.WatchEvent;
const report = @import("report.zig");
const SseServer = @import("server.zig").SseServer;

/// Per-path persistent state for watch mode.
/// Heap-allocated so that entries_mutex has a stable address for thread pool jobs.
const PathWatchState = struct {
    root_path: []const u8,
    md_path: []const u8,
    file_entries: std.StringHashMap(JobEntry),
    binary_entries: std.StringHashMap(BinaryEntry),
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
        const md_path = try report.resolveOutputPath(allocator, cfg, path, output_filename);
        errdefer allocator.free(md_path);

        const self = try allocator.create(PathWatchState);
        self.* = .{
            .root_path = try allocator.dupe(u8, path),
            .md_path = md_path,
            .file_entries = std.StringHashMap(JobEntry).init(allocator),
            .binary_entries = std.StringHashMap(BinaryEntry).init(allocator),
            .entries_mutex = .{},
            .file_ctx = .{
                .ignore_list = .{},
                .md = undefined,
                .md_mutex = undefined,
            },
            .allocator = allocator,
        };

        // Build ignore list — order matches runner.zig: output dir, md, json, html, llm, user patterns
        const base_output_dir: []const u8 = if (cfg.output_dir) |d| d else "zigzag-reports";
        const output_dir_ignore = try allocator.dupe(u8, base_output_dir);
        try self.file_ctx.ignore_list.append(allocator, output_dir_ignore);

        const owned_md = try allocator.dupe(u8, md_path);
        try self.file_ctx.ignore_list.append(allocator, owned_md);

        if (cfg.json_output) {
            const json_ignore_path = try report.deriveJsonPath(allocator, md_path);
            try self.file_ctx.ignore_list.append(allocator, json_ignore_path);
        }

        if (cfg.html_output) {
            const html_ignore_path = try report.deriveHtmlPath(allocator, md_path);
            try self.file_ctx.ignore_list.append(allocator, html_ignore_path);
        }

        if (cfg.llm_report) {
            const llm_ignore_path = try report.deriveLlmPath(allocator, md_path);
            try self.file_ctx.ignore_list.append(allocator, llm_ignore_path);
        }

        for (cfg.ignore_patterns.items) |pattern| {
            const owned = try allocator.dupe(u8, pattern);
            try self.file_ctx.ignore_list.append(allocator, owned);
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
            .binary_entries = &self.binary_entries,
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

        var bit = self.binary_entries.iterator();
        while (bit.next()) |entry| {
            std.heap.page_allocator.free(entry.value_ptr.path);
            std.heap.page_allocator.free(entry.value_ptr.extension);
        }
        self.binary_entries.deinit();

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
        if (self.binary_entries.fetchRemove(file_path)) |kv| {
            std.heap.page_allocator.free(kv.value.path);
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
            .binary_entries = &self.binary_entries,
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
        if (self.binary_entries.fetchRemove(file_path)) |kv| {
            std.heap.page_allocator.free(kv.value.path);
            std.heap.page_allocator.free(kv.value.extension);
        }
    }

    /// Build ReportData once and write all enabled report formats.
    /// The optional sse_server receives the SSE payload when html_output is active.
    fn writeAllReports(
        self: *PathWatchState,
        cfg: *const Config,
        sse_server: ?*SseServer,
        allocator: std.mem.Allocator,
    ) void {
        var report_data = report.ReportData.init(
            allocator,
            &self.file_entries,
            &self.binary_entries,
            cfg.timezone_offset,
        ) catch |err| {
            std.log.err("Failed to aggregate report data for '{s}': {s}", .{ self.root_path, @errorName(err) });
            return;
        };
        defer report_data.deinit();

        report.writeReport(&report_data, &self.file_entries, self.md_path, self.root_path, cfg, allocator) catch |err| {
            std.log.err("Failed to write report for '{s}': {s}", .{ self.root_path, @errorName(err) });
        };

        if (cfg.json_output) {
            const json_path = report.deriveJsonPath(allocator, self.md_path) catch null;
            if (json_path) |jp| {
                defer allocator.free(jp);
                report.writeJsonReport(&report_data, jp, self.root_path, cfg, allocator) catch |err| {
                    std.log.err("Failed to write JSON report for '{s}': {s}", .{ self.root_path, @errorName(err) });
                };
            }
        }

        if (cfg.html_output) {
            const html_path = report.deriveHtmlPath(allocator, self.md_path) catch null;
            if (html_path) |hp| {
                defer allocator.free(hp);
                report.writeHtmlReport(&report_data, hp, self.root_path, cfg, allocator) catch |err| {
                    std.log.err("Failed to write HTML report for '{s}': {s}", .{ self.root_path, @errorName(err) });
                };
                if (sse_server) |srv| {
                    const payload = report.buildSsePayload(&report_data, self.root_path, cfg, allocator) catch null;
                    if (payload) |p| {
                        defer allocator.free(p);
                        srv.broadcast(p);
                    }
                }
            }
        }

        if (cfg.llm_report) {
            const llm_path = report.deriveLlmPath(allocator, self.md_path) catch null;
            if (llm_path) |lp| {
                defer allocator.free(lp);
                report.writeLlmReport(&report_data, self.binary_entries.count(), lp, self.root_path, cfg, allocator) catch |err| {
                    std.log.err("Failed to write LLM report for '{s}': {s}", .{ self.root_path, @errorName(err) });
                };
            }
        }
    }
};

/// Event-driven watch mode: uses OS filesystem events (inotify/kqueue/ReadDirectoryChangesW)
/// for incremental updates. Keeps all file content in memory; only re-reads changed files.
pub fn execWatch(cfg: *const Config, cache: ?*CacheImpl) !void {
    if (cfg.paths.items.len == 0) return;

    const allocator = std.heap.page_allocator;

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
        // Write initial reports (no SSE server yet — will be started after all paths init)
        state.writeAllReports(cfg, null, allocator);
    }

    if (states.items.len == 0) return;

    // --- Start SSE dev server when both --watch and --html are active ---
    var sse_server: ?*SseServer = null;
    if (cfg.html_output) {
        const first_html_path = report.deriveHtmlPath(allocator, states.items[0].md_path) catch null;
        defer if (first_html_path) |p| allocator.free(p);

        if (first_html_path) |hp| {
            sse_server = SseServer.init(cfg.serve_port, hp, allocator) catch |err| blk: {
                std.log.warn("SSE server failed to start on port {d}: {s}", .{ cfg.serve_port, @errorName(err) });
                break :blk null;
            };
            if (sse_server) |srv| {
                srv.start() catch |err| {
                    std.log.warn("SSE server thread failed: {s}", .{@errorName(err)});
                    srv.deinit();
                    sse_server = null;
                };
                if (sse_server != null) {
                    std.log.info("Dashboard: http://127.0.0.1:{d}", .{cfg.serve_port});
                    // Broadcast initial payload so connecting clients get data immediately.
                    const first = states.items[0];
                    var init_data = report.ReportData.init(allocator, &first.file_entries, &first.binary_entries, cfg.timezone_offset) catch null;
                    if (init_data) |*d| {
                        defer d.deinit();
                        const payload = report.buildSsePayload(d, first.root_path, cfg, allocator) catch null;
                        if (payload) |p| {
                            defer allocator.free(p);
                            sse_server.?.broadcast(p);
                        }
                    }
                }
            }
        }
    }
    defer if (sse_server) |srv| srv.deinit();

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
    const DEBOUNCE_MS: i32 = 50;

    while (true) {
        events.clearRetainingCapacity();

        const timeout: i32 = if (dirty) DEBOUNCE_MS else -1;
        const n = watcher.poll(&events, timeout) catch |err| {
            std.log.err("Watcher poll error: {s}", .{@errorName(err)});
            continue;
        };

        if (n > 0) {
            for (events.items) |event| {
                defer allocator.free(event.path);

                if (std.mem.indexOf(u8, event.path, ".cache") != null) continue;
                if (std.mem.indexOf(u8, event.path, ".zig-cache") != null) continue;
                const base_out_dir: []const u8 = if (cfg.output_dir) |d| d else "zigzag-reports";
                if (std.mem.indexOf(u8, event.path, base_out_dir) != null) continue;

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
                state.writeAllReports(cfg, sse_server, allocator);
            }
            dirty = false;
        }
    }
}

// ============================================================
// Tests
// ============================================================

test "PathWatchState.removeFile removes entry from map and frees memory" {
    // processFileJob uses page_allocator for entry slices; removeFile mirrors that
    const page_alloc = std.heap.page_allocator;

    var state: PathWatchState = undefined;
    state.entries_mutex = .{};
    state.allocator = std.testing.allocator;
    state.file_entries = std.StringHashMap(JobEntry).init(std.testing.allocator);
    defer state.file_entries.deinit();
    state.binary_entries = std.StringHashMap(BinaryEntry).init(std.testing.allocator);
    defer state.binary_entries.deinit();

    const path = try page_alloc.dupe(u8, "src/target.zig");
    const content = try page_alloc.dupe(u8, "pub fn run() void {}");
    const ext = try page_alloc.dupe(u8, ".zig");

    try state.file_entries.put(path, JobEntry{
        .path = path,
        .content = content,
        .size = 20,
        .mtime = 0,
        .extension = ext,
        .line_count = 1,
    });

    try std.testing.expectEqual(@as(usize, 1), state.file_entries.count());
    state.removeFile("src/target.zig");
    try std.testing.expectEqual(@as(usize, 0), state.file_entries.count());
}

test "PathWatchState.removeFile is a no-op for unknown paths" {
    var state: PathWatchState = undefined;
    state.entries_mutex = .{};
    state.allocator = std.testing.allocator;
    state.file_entries = std.StringHashMap(JobEntry).init(std.testing.allocator);
    defer state.file_entries.deinit();
    state.binary_entries = std.StringHashMap(BinaryEntry).init(std.testing.allocator);
    defer state.binary_entries.deinit();

    state.removeFile("nonexistent/path.zig");
    try std.testing.expectEqual(@as(usize, 0), state.file_entries.count());
}

pub fn test_function() void {}
