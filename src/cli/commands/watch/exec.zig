const std = @import("std");
const State = @import("State.zig");
const reporter = @import("reporter.zig");
const Config = @import("../config/Config.zig");
const Pool = @import("../../../workers/Pool.zig");
const Cache = @import("../../../cache/Cache.zig");
const watcher_mod = @import("../../../platform/watcher.zig");
const Watcher = watcher_mod.Watcher;
const WatchLoop = @import("WatchLoop.zig");
const report = @import("../report.zig");
const Server = @import("Server.zig");
const isPortListening = @import("port_listening.zig").isPortListening;
const lg = @import("../../../utils/utils.zig");
const log = @import("../../../logger/Logger.zig");
const Progress = lg.Progress;
const Stats = @import("../stats.zig").Stats;
const nsElapsed = lg.nsElapsed;

/// Event-driven watch mode: uses OS filesystem events (inotify/kqueue/ReadDirectoryChangesW)
/// for incremental updates. Keeps all file content in memory; only re-read changed files.
pub fn execWatch(io: std.Io, cfg: *Config, cache: ?*Cache, allocator: std.mem.Allocator) !void {
    if (cfg.paths.items.len == 0) return;

    var pool = Pool{};
    try pool.init(io, .{ .allocator = allocator, .n_jobs = cfg.n_threads });
    defer pool.deinit();

    // Scan phase progress is suppressed on TTY (same rationale as runner.zig: worker
    // thread output between printPhaseStart and printPhaseDone corrupts cursor-up rewrite).
    const is_tty = (std.Io.File.stderr().isTty(io) catch false);

    // Scan all configured paths for initial state.
    var states: std.ArrayList(*State) = .empty;
    defer {
        for (states.items) |s| s.deinit();
        states.deinit(allocator);
    }

    for (cfg.paths.items) |path| {
        const state = (try scanPath(io, cfg, cache, &pool, path, is_tty, allocator)) orelse continue;
        try states.append(allocator, state);
        // Write initial reports (no SSE server yet — will be started after all paths init)
        reporter.writeAllReports(io, state, cfg, null, &.{}, allocator);
    }

    if (states.items.len == 0) return;

    const base_out_dir: []const u8 = if (cfg.output_dir) |d| d else "zigzag-reports";

    // Flush cache to disk now so it survives Ctrl+C during the watch loop.
    // Without this, defer cache.deinit() in main.zig never runs on SIGINT.
    if (cache) |c| c.saveToDisk() catch {};

    // Write combined HTML report (initial, before SSE server starts).
    reporter.writeCombinedReport(io, states.items, cfg, null, &.{}, allocator);

    // Start the SSE dev server (port probe + initial broadcast) when --html is active.
    const sse_server: ?*Server = if (cfg.html_output)
        startServer(io, cfg, states.items, base_out_dir, allocator)
    else
        null;
    defer if (sse_server) |srv| srv.deinit();

    // Re-write reports now that the SSE server port is finalized.
    // The initial write (before server start) may have baked in the default port,
    // but port fallback can change cfg.serve_port — the HTML sse_url must match.
    if (sse_server != null) {
        for (states.items) |state| {
            reporter.writeAllReports(io, state, cfg, null, &.{}, allocator);
        }
        if (states.items.len > 1) {
            reporter.writeCombinedReport(io, states.items, cfg, null, &.{}, allocator);
        }
    }

    // Set up OS-level filesystem watcher
    var watcher = try Watcher.init(io, allocator);
    defer watcher.deinit();

    // Register the report output directory as a skip path before adding watches.
    // Without this, every flush that writes content-sidecar JSON files (one per source
    // file) generates thousands of CLOSE_WRITE events into the inotify queue, easily
    // exceeding max_queued_events (default 16384) and causing a continuous overflow loop.
    watcher.addSkipDir(base_out_dir) catch {};

    for (states.items) |state| {
        watcher.watchDir(state.root_path) catch |err| {
            log.err(io, "Failed to watch '{s}': {s}", .{ state.root_path, @errorName(err) });
        };
    }

    log.success(io, "Watching {d} path(s) — press Ctrl+C to stop", .{states.items.len});

    var loop = try WatchLoop.init(allocator, io, cfg, cache, &pool, states.items, sse_server, base_out_dir, &watcher);
    defer loop.deinit();
    loop.run();
}

/// Scan one configured path into a State, driving the progress bar and phase logging.
/// Returns null (after logging) when the path can't be initialized; the outer error is
/// reserved for progress-bar startup failures, which abort the whole watch.
fn scanPath(
    io: std.Io,
    cfg: *const Config,
    cache: ?*Cache,
    pool: *Pool,
    path: []const u8,
    is_tty: bool,
    allocator: std.mem.Allocator,
) !?*State {
    const t_scan = std.Io.Timestamp.now(io, .real).nanoseconds;
    if (!is_tty) log.phaseStart(io, "Scanning {s}...", .{path});

    var stats = Stats.init();
    var pb = Progress.init(io, &stats); // pb must not be moved after this line
    try pb.start();

    const state = State.init(allocator, io, &stats, cfg, cache, path, pool) catch |err| {
        pb.stop();
        if (!is_tty) log.phaseDone(io, nsElapsed(io, t_scan), "", .{});
        switch (err) {
            error.NotADirectory => log.err(io, "Path '{s}' is not a directory", .{path}),
            else => log.err(io, "Failed to init watch state for '{s}': {s}", .{ path, @errorName(err) }),
        }
        return null;
    };

    pb.stop();
    if (!is_tty) log.phaseDone(io, nsElapsed(io, t_scan), "{d} files", .{state.file_entries.count()});
    return state;
}

/// Bring up the SSE dev server: probe from cfg.serve_port for a free port, bind, start
/// the broadcast thread, and push an initial snapshot. Returns null (server not started)
/// on any failure; on success the caller owns the returned server and must deinit it.
fn startServer(
    io: std.Io,
    cfg: *Config,
    states: []const *State,
    base_out_dir: []const u8,
    allocator: std.mem.Allocator,
) ?*Server {
    const multi = states.len > 1;

    // For multi-path: serve from base output dir so combined-content.json is at root.
    // For single path: serve from per-path subdir so report-content.json is at root.
    var first_html_buf: ?[]u8 = null;
    defer if (first_html_buf) |b| allocator.free(b);
    const srv_root: []const u8 = if (multi) base_out_dir else blk: {
        first_html_buf = report.deriveHtmlPath(allocator, states[0].md_path) catch null;
        if (first_html_buf) |hp| break :blk std.fs.path.dirname(hp) orelse base_out_dir;
        break :blk base_out_dir;
    };
    const default_page: []const u8 = if (multi) "combined.html" else "report.html";

    const srv = bindServer(io, cfg, srv_root, default_page, allocator) orelse return null;

    srv.start() catch |err| {
        log.warn(io, "SSE server thread failed: {s}", .{@errorName(err)});
        srv.deinit();
        return null;
    };

    log.success(io, "Dashboard  \x1b[4mhttp://127.0.0.1:{d}\x1b[0m", .{cfg.serve_port});
    if (cfg.open_browser) srv.openBrowser();

    broadcastInitialSnapshot(io, cfg, states, srv, allocator);
    return srv;
}

/// Probe upward from cfg.serve_port for a free port and bind the server there.
/// Updates cfg.serve_port when it lands on a fallback port so HTML/SSE-URL generation
/// stays in sync. Returns null when every candidate port is occupied or bind fails.
///
/// Uses a TCP connection probe rather than relying on bind() error codes.
/// SO_REUSEADDR can allow duplicate binds on some OS/kernel configurations.
fn bindServer(
    io: std.Io,
    cfg: *Config,
    srv_root: []const u8,
    default_page: []const u8,
    allocator: std.mem.Allocator,
) ?*Server {
    const max_port_attempts = 10;
    var port = cfg.serve_port;
    for (0..max_port_attempts) |i| {
        if (isPortListening(io, port)) {
            if (i == 0) {
                log.warn(io, "Port {d} already in use, trying port {d}..{d}...", .{ port, port + 1, port + max_port_attempts - 1 });
            }
            if (i == max_port_attempts - 1) {
                log.err(io, "Ports {d}..{d} are all occupied. Cannot start SSE server.", .{ cfg.serve_port, port });
                return null;
            }
            port += 1;
            continue;
        }
        if (Server.init(io, port, srv_root, default_page, allocator)) |srv| {
            if (port != cfg.serve_port) cfg.serve_port = port; // propagate to HTML/SSE-URL generation
            return srv;
        } else |err| {
            // Bind still failed (race condition or other error); treat as occupied.
            if (err == error.AddressInUse) {
                if (i == 0) {
                    log.warn(io, "Port {d} already in use, trying port {d}..{d}...", .{ port, port + 1, port + max_port_attempts - 1 });
                }
                port += 1;
            } else {
                log.warn(io, "SSE server failed to start on port {d}: {s}", .{ port, @errorName(err) });
                return null;
            }
        }
    }
    return null;
}

/// Broadcast the first state's full payload so clients that connect immediately get data.
fn broadcastInitialSnapshot(io: std.Io, cfg: *const Config, states: []const *State, srv: *Server, allocator: std.mem.Allocator) void {
    const first = states[0];
    var init_data = report.ReportData.init(io, allocator, &first.file_entries, &first.binary_entries, cfg.timezone_offset) catch return;
    defer init_data.deinit();
    const payload = report.buildSsePayload(&init_data, first.root_path, cfg, allocator) catch return;
    defer allocator.free(payload);
    srv.broadcast(payload);
}
