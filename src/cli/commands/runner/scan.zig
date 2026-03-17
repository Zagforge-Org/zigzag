const std = @import("std");
const walk = @import("../../../fs/walk.zig").Walk;
const walkerCallback = @import("../../../walker/callback.zig").walkerCallback;
const Config = @import("../config/config.zig").Config;
const FileContext = @import("../../context.zig").FileContext;
const Pool = @import("../../../workers/pool.zig").Pool;
const WaitGroup = @import("../../../workers/wait_group.zig").WaitGroup;
const CacheImpl = @import("../../../cache/impl.zig").CacheImpl;
const ProcessStats = @import("../stats.zig").ProcessStats;
const JobEntry = @import("../../../jobs/entry.zig").JobEntry;
const BinaryEntry = @import("../../../jobs/entry.zig").BinaryEntry;
const WalkerCtx = @import("../../../walker/context.zig").WalkerCtx;
const report = @import("../report.zig");
const lg = @import("../../../utils/utils.zig");
const Logger = lg.Logger;

/// Nanoseconds elapsed since `start` (from nanoTimestamp). Clamped to 0.
pub inline fn nsElapsed(start: i128) u64 {
    const delta = std.time.nanoTimestamp() - start;
    return @intCast(@max(0, delta));
}

/// Owned result of scanning one path. Caller (exec) controls lifetime.
pub const ScanResult = struct {
    root_path: []const u8, // not owned — points into cfg.paths item
    file_entries: std.StringHashMap(JobEntry),
    binary_entries: std.StringHashMap(BinaryEntry),
    stats: ProcessStats,

    pub fn deinit(self: *ScanResult, allocator: std.mem.Allocator) void {
        var it = self.file_entries.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.value_ptr.path);
            allocator.free(entry.value_ptr.content);
            allocator.free(entry.value_ptr.extension);
        }
        self.file_entries.deinit();
        var bit = self.binary_entries.iterator();
        while (bit.next()) |entry| {
            allocator.free(entry.value_ptr.path);
            allocator.free(entry.value_ptr.extension);
        }
        self.binary_entries.deinit();
    }
};

/// Scan a single directory path and return collected entries. Caller owns the result.
pub fn scanPath(
    cfg: *const Config,
    cache: ?*CacheImpl,
    path: []const u8,
    pool: *Pool,
    allocator: std.mem.Allocator,
    logger: ?*Logger,
) !ScanResult {
    var dir = std.fs.cwd().openDir(path, .{}) catch {
        return error.NotADirectory;
    };
    defer dir.close();

    const output_filename: []const u8 = if (cfg.output) |o| o else "report.md";
    const md_path = try report.resolveOutputPath(allocator, cfg, path, output_filename);
    defer allocator.free(md_path);

    var file_ctx = FileContext{
        .ignore_list = .{},
        .md = undefined,
        .md_mutex = undefined,
    };
    defer {
        for (file_ctx.ignore_list.items) |item| allocator.free(item);
        file_ctx.ignore_list.deinit(allocator);
    }

    // Auto-ignore the output directory to prevent scanning report artifacts.
    // This also excludes combined.html and combined-content.json which live
    // directly inside base_output_dir (not in a per-path subdirectory).
    const base_output_dir: []const u8 = if (cfg.output_dir) |d| d else "zigzag-reports";
    const output_dir_ignore = try allocator.dupe(u8, base_output_dir);
    try file_ctx.ignore_list.append(allocator, output_dir_ignore);

    const owned_md_path = try allocator.dupe(u8, md_path);
    try file_ctx.ignore_list.append(allocator, owned_md_path);

    if (cfg.json_output) {
        const json_ignore = try report.deriveJsonPath(allocator, md_path);
        try file_ctx.ignore_list.append(allocator, json_ignore);
    }

    if (cfg.html_output) {
        const html_ignore = try report.deriveHtmlPath(allocator, md_path);
        try file_ctx.ignore_list.append(allocator, html_ignore);
        // Also ignore the content sidecar so it doesn't appear as source
        const content_ignore = try report.deriveContentPath(allocator, html_ignore);
        try file_ctx.ignore_list.append(allocator, content_ignore);
    }

    if (cfg.llm_report) {
        const llm_ignore = try report.deriveLlmPath(allocator, md_path);
        try file_ctx.ignore_list.append(allocator, llm_ignore);
    }

    for (cfg.ignore_patterns.items) |pattern| {
        const owned_pattern = try allocator.dupe(u8, pattern);
        try file_ctx.ignore_list.append(allocator, owned_pattern);
    }

    var wg = WaitGroup.init();
    var stats = ProcessStats.init();

    var file_entries = std.StringHashMap(JobEntry).init(allocator);
    errdefer {
        var it = file_entries.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.value_ptr.path);
            allocator.free(entry.value_ptr.content);
            allocator.free(entry.value_ptr.extension);
        }
        file_entries.deinit();
    }

    var binary_entries = std.StringHashMap(BinaryEntry).init(allocator);
    errdefer {
        var it = binary_entries.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.value_ptr.path);
            allocator.free(entry.value_ptr.extension);
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

    var pb = lg.ProgressBar.init(&stats); // pb must not be moved after this line
    try pb.start();
    try walker.walkDir(path, walkerCallback, walk_ctx);
    wg.wait();
    pb.stop();

    // Log each processed file to the log file
    if (logger) |l| {
        var it = file_entries.iterator();
        while (it.next()) |entry| {
            l.log("  file: {s} ({d} bytes, {d} lines)", .{
                entry.value_ptr.path,
                entry.value_ptr.content.len,
                entry.value_ptr.line_count,
            });
        }
    }

    return ScanResult{
        .root_path = path,
        .file_entries = file_entries,
        .binary_entries = binary_entries,
        .stats = stats,
    };
}
