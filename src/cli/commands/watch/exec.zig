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
const isPortListening = @import("port_listening.zig").isPortListening;
const lg = @import("../../../utils/utils.zig");
const ProgressBar = lg.ProgressBar;
const ProcessStats = @import("../stats.zig").ProcessStats;

inline fn nsElapsed(start: i128) u64 {
    const delta = std.time.nanoTimestamp() - start;
    return @intCast(@max(0, delta));
}

/// Event-driven watch mode: uses OS filesystem events (inotify/kqueue/ReadDirectoryChangesW)
/// for incremental updates. Keeps all file content in memory; only re-read changed files.
pub fn execWatch(cfg: *Config, cache: ?*CacheImpl, allocator: std.mem.Allocator) !void {
    if (cfg.paths.items.len == 0) return;

    var pool = Pool{};
    try pool.init(.{ .allocator = allocator, .n_jobs = cfg.n_threads });
    defer pool.deinit();

    // Scan phase progress is suppressed on TTY (same rationale as runner.zig: worker
    // thread output between printPhaseStart and printPhaseDone corrupts cursor-up rewrite).
    const is_tty = std.posix.isatty(std.fs.File.stderr().handle);

    // Scan all configured paths for initial state.
    var states: std.ArrayList(*State) = .empty;
    defer {
        for (states.items) |s| s.deinit();
        states.deinit(allocator);
    }

    for (cfg.paths.items) |path| {
        const t_scan = std.time.nanoTimestamp();
        if (!is_tty) lg.printPhaseStart("Scanning {s}...", .{path});
        var stats = ProcessStats.init();
        var pb = ProgressBar.init(&stats); // pb must not be moved after this line
        try pb.start();
        const state = blk: {
            if (State.init(&stats, cfg, cache, path, &pool, allocator)) |s| {
                pb.stop();
                if (!is_tty) lg.printPhaseDone(nsElapsed(t_scan), "{d} files", .{s.file_entries.count()});
                break :blk s;
            } else |err| {
                pb.stop();
                if (!is_tty) lg.printPhaseDone(nsElapsed(t_scan), "", .{});
                switch (err) {
                    error.NotADirectory => lg.printError("Path '{s}' is not a directory", .{path}),
                    else => lg.printError("Failed to init watch state for '{s}': {s}", .{ path, @errorName(err) }),
                }
                continue;
            }
        };
        try states.append(allocator, state);
        // Write initial reports (no SSE server yet — will be started after all paths init)
        reporter.writeAllReports(state, cfg, null, &.{}, allocator);
    }

    if (states.items.len == 0) return;

    // Flush cache to disk now so it survives Ctrl+C during the watch loop.
    // Without this, defer cache.deinit() in main.zig never runs on SIGINT.
    if (cache) |c| c.saveToDisk() catch {};

    // Write combined HTML report (initial, before SSE server starts).
    reporter.writeCombinedReport(states.items, cfg, null, &.{}, allocator);

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
            // Try the configured port; if already in use, increment up to 9 more times.
            // Use a TCP connection probe rather than relying on bind() error codes —
            // SO_REUSEADDR can allow duplicate binds on some OS/kernel configurations.
            const max_port_attempts = 10;
            var port = cfg.serve_port;
            for (0..max_port_attempts) |i| {
                if (isPortListening(port)) {
                    if (i == 0) {
                        lg.printWarn("Port {d} already in use, trying port {d}..{d}...", .{ port, port + 1, port + max_port_attempts - 1 });
                    }
                    if (i == max_port_attempts - 1) {
                        lg.printError("Ports {d}..{d} are all occupied. Cannot start SSE server.", .{ cfg.serve_port, port });
                        break;
                    }
                    port += 1;
                    continue;
                }
                if (SseServer.init(port, srv_root, default_page, allocator)) |srv| {
                    sse_server = srv;
                    if (port != cfg.serve_port) {
                        cfg.serve_port = port; // propagate to HTML/SSE-URL generation
                    }
                    break;
                } else |err| {
                    // Bind still failed (race condition or other error); treat as occupied.
                    if (err == error.AddressInUse) {
                        if (i == 0) {
                            lg.printWarn("Port {d} already in use, trying port {d}..{d}...", .{ port, port + 1, port + max_port_attempts - 1 });
                        }
                        port += 1;
                    } else {
                        lg.printWarn("SSE server failed to start on port {d}: {s}", .{ port, @errorName(err) });
                        break;
                    }
                }
            }
            if (sse_server) |srv| {
                srv.start() catch |err| {
                    lg.printWarn("SSE server thread failed: {s}", .{@errorName(err)});
                    srv.deinit();
                    sse_server = null;
                };
                if (sse_server != null) {
                    lg.printSuccess("Dashboard  \x1b[4mhttp://127.0.0.1:{d}\x1b[0m", .{cfg.serve_port});
                    if (cfg.open_browser) sse_server.?.openBrowser();
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

    // Register the report output directory as a skip path before adding watches.
    // Without this, every flush that writes content-sidecar JSON files (one per source
    // file) generates thousands of CLOSE_WRITE events into the inotify queue, easily
    // exceeding max_queued_events (default 16384) and causing a continuous overflow loop.
    {
        const base_out_dir: []const u8 = if (cfg.output_dir) |d| d else "zigzag-reports";
        watcher.addSkipDir(base_out_dir) catch {};
    }

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

    // Per-state dirty flags so only changed paths get their reports rebuilt.
    const dirty_states = try allocator.alloc(bool, states.items.len);
    defer allocator.free(dirty_states);
    @memset(dirty_states, false);
    var any_dirty = false;

    // Track which file paths changed in the current debounce window so the report
    // writer only re-writes those content sidecar files instead of all of them.
    // On overflow (events lost) we fall back to writing all sidecars.
    var changed_paths: std.ArrayList([]const u8) = .empty;
    defer {
        for (changed_paths.items) |p| allocator.free(p);
        changed_paths.deinit(allocator);
    }
    var any_overflow = false;

    const DEBOUNCE_MS: i32 = 50;

    while (true) {
        events.clearRetainingCapacity();

        const timeout: i32 = if (any_dirty) DEBOUNCE_MS else -1;
        const n = watcher.poll(&events, timeout) catch |err| {
            lg.printError("Watcher poll error: {s}", .{@errorName(err)});
            continue;
        };

        // Handle inotify queue overflow: mark all states dirty and let the debounce
        // flush rebuild reports from current in-memory state.
        //
        // Do NOT rescan or re-watch here. Both block the event loop for seconds (full
        // directory walk + thread-pool cache writes), which generates more inotify events
        // while the kernel queue is still full — causing the queue to overflow again
        // immediately, creating an infinite overflow → heavy-work → overflow loop.
        //
        // The kernel does not remove existing watches on overflow, so all directory
        // watches remain valid. Any new directories created during the overflow window
        // will be picked up automatically when the next CREATE+ISDIR event arrives.
        if (watcher.overflow) {
            watcher.overflow = false;
            any_overflow = true;
            for (0..states.items.len) |i| dirty_states[i] = true;
            any_dirty = true;
        }

        if (n > 0) {
            for (events.items) |event| {
                defer allocator.free(event.path);

                if (std.mem.indexOf(u8, event.path, ".cache") != null) continue;
                if (std.mem.indexOf(u8, event.path, ".zig-cache") != null) continue;
                const base_out_dir: []const u8 = if (cfg.output_dir) |d| d else "zigzag-reports";
                if (std.mem.indexOf(u8, event.path, base_out_dir) != null) continue;

                for (states.items, 0..) |state, i| {
                    if (!std.mem.startsWith(u8, event.path, state.root_path)) continue;

                    switch (event.kind) {
                        .created, .modified => {
                            state.updateFile(event.path, cache, &pool) catch |err| {
                                lg.printError("Failed to process {s}: {s}", .{ event.path, @errorName(err) });
                            };
                            // Track the changed path for selective sidecar writes on debounce.
                            const path_copy = allocator.dupe(u8, event.path) catch null;
                            if (path_copy) |p| changed_paths.append(allocator, p) catch allocator.free(p);
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
                    dirty_states[i] = true;
                    any_dirty = true;
                    break;
                }
            }
        } else if (any_dirty) {
            // Quiet period elapsed — write reports only for paths that actually changed.
            // Write combined report FIRST so it is on disk before the SSE "report" event
            // fires and causes connected browsers to reload combined.html.
            var combined_needed = false;
            for (0..states.items.len) |i| {
                if (dirty_states[i]) {
                    combined_needed = true;
                    break;
                }
            }
            // On overflow, changed_paths is incomplete — pass empty slice so all sidecars
            // get written, ensuring the content directory is consistent.
            const paths_for_write: []const []const u8 = if (any_overflow) &.{} else changed_paths.items;
            if (combined_needed and states.items.len > 1) {
                // Only write and signal the combined dashboard in multi-path mode.
                // Single-path watch uses SSE deltas and the per-state report event instead.
                // writeCombinedReport handles the broadcastCombined SSE push internally.
                reporter.writeCombinedReport(states.items, cfg, sse_server, paths_for_write, allocator);
            }
            for (states.items, 0..) |state, i| {
                if (!dirty_states[i]) continue;
                reporter.writeAllReports(state, cfg, sse_server, paths_for_write, allocator);
                dirty_states[i] = false;
            }
            any_dirty = false;
            any_overflow = false;
            for (changed_paths.items) |p| allocator.free(p);
            changed_paths.clearRetainingCapacity();
        }
    }
}
