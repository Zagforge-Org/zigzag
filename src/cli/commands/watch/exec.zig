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
pub fn execWatch(cfg: *const Config, cache: ?*CacheImpl) !void {
    if (cfg.paths.items.len == 0) return;

    const allocator = std.heap.page_allocator;

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

    // Start SSE dev server when both --watch and --html are active
    var sse_server: ?*SseServer = null;
    if (cfg.html_output) {
        const first_html_path = report.deriveHtmlPath(allocator, states.items[0].md_path) catch null;
        defer if (first_html_path) |p| allocator.free(p);

        if (first_html_path) |hp| {
            sse_server = SseServer.init(cfg.serve_port, hp, allocator) catch |err| blk: {
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
                reporter.writeAllReports(state, cfg, sse_server, allocator);
            }
            dirty = false;
        }
    }
}
