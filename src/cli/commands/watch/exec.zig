const std = @import("std");
const State = @import("state.zig").State;
const reporter = @import("reporter.zig");
const Config = @import("../config/config.zig").Config;
const Pool = @import("../../../workers/pool.zig").Pool;
const CacheImpl = @import("../../../cache/impl.zig").CacheImpl;
const watcher_mod = @import("../../../fs/watcher.zig");
const Watcher = watcher_mod.Watcher;
const WatchEvent = watcher_mod.WatchEvent;
const report = @import("../report.zig");
const SseServer = @import("server.zig").SseServer;
const lg = @import("../logger.zig");

/// Event-driven watch mode: uses OS filesystem events (inotify/kqueue/ReadDirectoryChangesW)
/// for incremental updates. Keeps all file content in memory; only re-read changed files.
pub fn execWatch(cfg: *const Config, cache: ?*CacheImpl, allocator: std.mem.Allocator) !void {
    if (cfg.paths.items.len == 0) return;

    var pool = Pool{};
    try pool.init(.{ .allocator = allocator, .n_jobs = cfg.n_threads });
    defer pool.deinit();

    // Scan all configured paths for initial state.
    var states: std.ArrayList(*State) = .empty;
    defer {
        for (states.items) |s| s.deinit();
        states.deinit(allocator);
    }

    for (cfg.paths.items) |path| {
        const state = State.init(cfg, cache, path, &pool, allocator) catch |err| {
            switch (err) {
                error.NotADirectory => lg.printError("Path '{s}' is not a directory", .{path}),
                else => lg.printError("Failed to init watch state for '{s}': {s}", .{ path, @errorName(err) }),
            }
            continue;
        };
        try states.append(allocator, state);
        // Write initial reports (no SSE server yet — will be started after all paths init)
        reporter.writeAllReports(state, cfg, null, allocator);
    }

    if (states.items.len == 0) return;

    // Flush cache to disk now so it survives Ctrl+C during the watch loop.
    // Without this, defer cache.deinit() in main.zig never runs on SIGINT.
    if (cache) |c| c.saveToDisk() catch {};

    // Write combined HTML report (initial, before SSE server starts).
    reporter.writeCombinedReport(states.items, cfg, allocator);

    // Start SSE dev server when both --watch and --html are active
    var sse_server: ?*SseServer = null;
    if (cfg.html_output) {
        const base_out_dir: []const u8 = if (cfg.output_dir) |d| d else "zigzag-reports";
        const multi = states.items.len > 1;

        // For multi-path: serve from base output dir so combined-content.json is at root.
        // For single path: serve from per-path subdir so report-content.json is at root.
        var first_html_buf: ?[]u8 = null;
        defer if (first_html_buf) |b| allocator.free(b);
        const srv_root: []const u8 = if (multi) base_out_dir else blk: {
            first_html_buf = report.deriveHtmlPath(allocator, states.items[0].md_path) catch null;
            if (first_html_buf) |hp| break :blk std.fs.path.dirname(hp) orelse base_out_dir;
            break :blk base_out_dir;
        };
        const default_page: []const u8 = if (multi) "combined.html" else "report.html";

        {
            sse_server = SseServer.init(cfg.serve_port, srv_root, default_page, allocator) catch |err| blk: {
                lg.printWarn("SSE server failed to start on port {d}: {s}", .{ cfg.serve_port, @errorName(err) });
                break :blk null;
            };
            if (sse_server) |srv| {
                srv.start() catch |err| {
                    lg.printWarn("SSE server thread failed: {s}", .{@errorName(err)});
                    srv.deinit();
                    sse_server = null;
                };
                if (sse_server != null) {
                    lg.printSuccess("Dashboard  \x1b[4mhttp://127.0.0.1:{d}\x1b[0m", .{cfg.serve_port});
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

    // Set up OS-level filesystem watcher
    var watcher = try Watcher.init(allocator);
    defer watcher.deinit();

    for (states.items) |state| {
        watcher.watchDir(state.root_path) catch |err| {
            lg.printError("Failed to watch '{s}': {s}", .{ state.root_path, @errorName(err) });
        };
    }

    lg.printSuccess("Watching {d} path(s) — press Ctrl+C to stop", .{states.items.len});

    // Event loop with debounce to group multiple events into a single update.
    // Ensures that updates are not triggered by rapid-fire events and preserves CPU resources.
    var events: std.ArrayList(WatchEvent) = .empty;
    defer events.deinit(allocator);

    var dirty = false;
    const DEBOUNCE_MS: i32 = 50;

    while (true) {
        events.clearRetainingCapacity();

        const timeout: i32 = if (dirty) DEBOUNCE_MS else -1;
        const n = watcher.poll(&events, timeout) catch |err| {
            lg.printError("Watcher poll error: {s}", .{@errorName(err)});
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
                                lg.printError("Failed to process {s}: {s}", .{ event.path, @errorName(err) });
                            };
                            // Broadcast a small KB-sized delta immediately — no need to wait for debounce.
                            if (sse_server) |srv| {
                                state.entries_mutex.lock();
                                const entry_opt = state.file_entries.get(event.path);
                                state.entries_mutex.unlock();
                                if (entry_opt) |entry| {
                                    const delta = report.buildFileDeltaPayload(allocator, &entry, .updated) catch null;
                                    if (delta) |d| {
                                        defer allocator.free(d);
                                        srv.broadcast(d);
                                    }
                                }
                            }
                        },
                        .deleted => {
                            state.removeFile(event.path);
                            if (sse_server) |srv| {
                                const delta = report.buildFileDeletePayload(allocator, event.path) catch null;
                                if (delta) |d| {
                                    defer allocator.free(d);
                                    srv.broadcast(d);
                                }
                            }
                        },
                    }
                    dirty = true;
                    break;
                }
            }
        } else if (dirty) {
            // Quiet period elapsed — write all reports to disk.
            // SSE delta was already broadcast immediately on each file event above.
            for (states.items) |state| {
                reporter.writeAllReports(state, cfg, null, allocator);
            }
            reporter.writeCombinedReport(states.items, cfg, allocator);
            dirty = false;
        }
    }
}
