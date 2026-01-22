const std = @import("std");
const fs = @import("../fs/file.zig");
const walk = @import("../fs/walk.zig").Walk;
const Config = @import("config.zig").Config;
const Context = @import("context.zig").Context;
const Pool = @import("../workers/pool.zig").Pool;
const WaitGroup = @import("../workers/wait_group.zig").WaitGroup;
const FileCache = @import("../fs/cache.zig").FileCache;

fn basename(path: []const u8) []const u8 {
    var lastSlash: usize = 0;
    var i: usize = 0;
    while (i < path.len) : (i += 1) {
        if (path[i] == '/') lastSlash = i + 1;
    }
    return path[lastSlash..];
}

fn shouldIgnore(file: []const u8, ignore_list: std.ArrayList([]const u8)) bool {
    const name = basename(file);
    if (std.mem.indexOf(u8, file, ".cache") != null) return true;

    for (ignore_list.items) |pattern| {
        if (pattern.len >= 2 and pattern[0] == '*' and pattern[1] == '.') {
            const ext = pattern[1..];
            if (name.len >= ext.len and std.mem.eql(u8, name[name.len - ext.len ..], ext)) return true;
        } else {
            if (std.mem.indexOf(u8, file, pattern) != null) return true;
        }
    }
    return false;
}

const ProcessStats = struct {
    cached_files: std.atomic.Value(usize),
    processed_files: std.atomic.Value(usize),
    ignored_files: std.atomic.Value(usize),

    fn init() ProcessStats {
        return .{
            .cached_files = std.atomic.Value(usize).init(0),
            .processed_files = std.atomic.Value(usize).init(0),
            .ignored_files = std.atomic.Value(usize).init(0),
        };
    }

    fn printSummary(self: *const ProcessStats) void {
        const cached = self.cached_files.load(.monotonic);
        const processed = self.processed_files.load(.monotonic);
        const ignored = self.ignored_files.load(.monotonic);
        const total = cached + processed + ignored;

        std.log.info("=== Processing Summary ===", .{});
        std.log.info("Total files: {d}", .{total});
        std.log.info("Cached (from .cache): {d}", .{cached});
        std.log.info("Processed (updated): {d}", .{processed});
        std.log.info("Ignored: {d}", .{ignored});
    }
};

const FileEntry = struct {
    path: []const u8,
    content: []u8,
};

const FileJob = struct {
    path: []const u8,
    ctx: ?*Context,
    cache: *FileCache,
    stats: *ProcessStats,
    file_entries: *std.StringHashMap(FileEntry),
    entries_mutex: *std.Thread.Mutex,
    allocator: std.mem.Allocator,

    fn deinit(self: *FileJob) void {
        self.allocator.free(self.path);
    }
};

fn processFileJob(job: FileJob) anyerror!void {
    defer {
        var mutable_job = job;
        mutable_job.deinit();
    }

    const path = job.path;
    const ctx = job.ctx;
    const cache = job.cache;
    const stats = job.stats;
    const file_entries = job.file_entries;
    const entries_mutex = job.entries_mutex;

    if (ctx) |c| {
        if (shouldIgnore(path, c.ignore_list)) {
            _ = stats.ignored_files.fetchAdd(1, .monotonic);
            return;
        }
    }

    const allocator = std.heap.page_allocator;

    const stat = std.fs.cwd().statFile(path) catch |err| {
        std.log.debug("Failed to stat file {s}: {}", .{ path, err });
        return;
    };

    const mtime = @as(u64, @intCast(stat.mtime));
    const size = stat.size;

    const small_file_threshold = cache.small_file_threshold;
    var hash: ?[32]u8 = null;

    if (size > small_file_threshold) {
        hash = cache.hashFileContent(path) catch |err| {
            std.log.debug("Failed to hash file {s}: {}", .{ path, err });
            return;
        };
    }

    const is_cached = cache.isCached(path, mtime, size, hash) catch false;

    var content: []u8 = undefined;

    if (is_cached) {
        // Read from cache
        std.log.debug("Cached (reading from .cache): {s}", .{path});
        _ = stats.cached_files.fetchAdd(1, .monotonic);

        content = cache.getCachedContent(path) catch blk: {
            std.log.debug("Failed to read cache for {s}, reading original", .{path});
            // Fallback to reading original file
            break :blk fs.readFileAlloc(allocator, path) catch return;
        };
    } else {
        // Read original file and update cache
        std.log.info("Processing (reading original): {s}", .{path});
        _ = stats.processed_files.fetchAdd(1, .monotonic);

        content = fs.readFileAlloc(allocator, path) catch |err| {
            std.log.debug("Failed to read file {s}: {}", .{ path, err });
            return;
        };

        // Update cache
        cache.update(path, hash, mtime, size, content) catch |err| {
            std.log.debug("Failed to update cache for {s}: {}", .{ path, err });
        };
    }

    // Store for report generation
    entries_mutex.lock();
    defer entries_mutex.unlock();

    const path_copy = try allocator.dupe(u8, path);
    try file_entries.put(path_copy, .{
        .path = path_copy,
        .content = content, // Transfer ownership
    });
}

const WalkerCtx = struct {
    pool: *Pool,
    wg: *WaitGroup,
    file_ctx: *Context,
    cache: *FileCache,
    stats: *ProcessStats,
    file_entries: *std.StringHashMap(FileEntry),
    entries_mutex: *std.Thread.Mutex,
    allocator: std.mem.Allocator,
};

fn walkCallback(ctx: ?*Context, path: []const u8) anyerror!void {
    if (ctx) |c| {
        const walker_ctx: *WalkerCtx = @ptrCast(@alignCast(c));
        const path_copy = try walker_ctx.allocator.dupe(u8, path);
        errdefer walker_ctx.allocator.free(path_copy);

        const job = FileJob{
            .path = path_copy,
            .ctx = walker_ctx.file_ctx,
            .cache = walker_ctx.cache,
            .stats = walker_ctx.stats,
            .file_entries = walker_ctx.file_entries,
            .entries_mutex = walker_ctx.entries_mutex,
            .allocator = walker_ctx.allocator,
        };

        try walker_ctx.pool.spawnWg(walker_ctx.wg, processFileJob, .{job});
    }
}

pub fn exec(cfg: *const Config, cache: *FileCache) !void {
    const allocator = std.heap.page_allocator;

    const md_path = try std.fs.path.join(allocator, &.{
        cfg.path,
        "report.md",
    });
    defer allocator.free(md_path);

    var file_ctx = Context{
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

    var pool = Pool{};
    try pool.init(.{
        .allocator = allocator,
        .n_jobs = cfg.n_threads,
    });
    defer pool.deinit();

    var wg = WaitGroup.init();
    var stats = ProcessStats.init();

    var file_entries = std.StringHashMap(FileEntry).init(allocator);
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
        .pool = &pool,
        .wg = &wg,
        .file_ctx = &file_ctx,
        .cache = cache,
        .stats = &stats,
        .file_entries = &file_entries,
        .entries_mutex = &entries_mutex,
        .allocator = allocator,
    };

    const walker = try walk.init(allocator);
    const walk_ctx: ?*Context = @ptrCast(@alignCast(&walker_ctx));

    std.log.info("Config path: {s}", .{cfg.path});

    try walker.walkDir(cfg.path, walkCallback, walk_ctx);
    wg.wait();

    // Build report.md from all collected files
    std.log.info("Building report.md...", .{});

    var md_file = try std.fs.cwd().createFile(md_path, .{ .truncate = true });
    defer md_file.close();

    var it = file_entries.iterator();
    while (it.next()) |entry| {
        try md_file.writeAll(entry.value_ptr.content);
    }

    stats.printSummary();
}
