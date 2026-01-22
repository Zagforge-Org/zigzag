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

    // Always ignore .cache directory
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

fn processChunk(_: []const u8) void {
    // Process the chunk of data here
}

/// Stats for tracking cache performance
/// Uses atomic values because multiple threads update these counters
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
        std.log.info("Cached (skipped): {d}", .{cached});
        std.log.info("Processed: {d}", .{processed});
        std.log.info("Ignored: {d}", .{ignored});
    }
};

// Structure to hold both the path and context - path is owned and will be freed
const FileJob = struct {
    path: []const u8,
    ctx: ?*Context,
    cache: *FileCache,
    stats: *ProcessStats,
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

    // Check if file should be ignored BEFORE doing anything else
    if (ctx) |c| {
        if (shouldIgnore(path, c.ignore_list)) {
            _ = stats.ignored_files.fetchAdd(1, .monotonic);
            return;
        }
    }

    const allocator = std.heap.page_allocator;

    // Get file metadata WITHOUT opening the file
    // This avoids any file handle issues
    const stat = std.fs.cwd().statFile(path) catch |err| {
        std.log.debug("Failed to stat file {s}: {}", .{ path, err });
        return;
    };

    const mtime = @as(u64, @intCast(stat.mtime));
    const size = stat.size;

    // Determine if we need to hash (large file)
    const small_file_threshold = cache.small_file_threshold;
    var hash: ?[32]u8 = null;

    if (size > small_file_threshold) {
        // Large file - compute hash
        // hashFileContent opens and closes its own file handle
        hash = cache.hashFileContent(path) catch |err| {
            std.log.debug("Failed to hash file {s}: {}", .{ path, err });
            return;
        };
    }

    // Check if file is cached
    const is_cached = cache.isCached(path, mtime, size, hash) catch false;

    if (is_cached) {
        // File hasn't changed, skip processing
        _ = stats.cached_files.fetchAdd(1, .monotonic);
        return;
    }

    // File is new or changed, process it
    std.log.info("Processing: {s}", .{path});
    _ = stats.processed_files.fetchAdd(1, .monotonic);

    // Process the file
    // readFileAuto opens and closes its own file handle
    var result = fs.readFileAuto(allocator, path, processChunk) catch |err| {
        std.log.debug("Failed to process file {s}: {}", .{ path, err });
        return;
    };
    switch (result) {
        .Alloc => |data| {
            defer allocator.free(data);
        },
        .Mapped => |*mapped| {
            defer mapped.deinit();
        },
        .Chunked => {},
    }

    // Update cache after successful processing
    cache.update(path, hash, mtime, size) catch |err| {
        std.log.debug("Failed to update cache for {s}: {}", .{ path, err });
    };
}

/// Context for the walker, passing pool + waitgroup + file context + allocator + cache + stats
const WalkerCtx = struct {
    pool: *Pool,
    wg: *WaitGroup,
    file_ctx: *Context,
    cache: *FileCache,
    stats: *ProcessStats,
    allocator: std.mem.Allocator,
};

/// Callback for each file found by walkDir
fn walkCallback(path: []const u8, ctx: ?*Context) anyerror!void {
    if (ctx) |c| {
        const walker_ctx: *WalkerCtx = @ptrCast(@alignCast(c));
        // Duplicate the path string since it's temporary
        const path_copy = try walker_ctx.allocator.dupe(u8, path);
        errdefer walker_ctx.allocator.free(path_copy);

        const job = FileJob{
            .path = path_copy,
            .ctx = walker_ctx.file_ctx,
            .cache = walker_ctx.cache,
            .stats = walker_ctx.stats,
            .allocator = walker_ctx.allocator,
        };

        // Submit job to thread pool
        try walker_ctx.pool.spawnWg(walker_ctx.wg, processFileJob, .{job});
    }
}

/// Main execution function
pub fn exec(cfg: *const Config, cache: *FileCache) !void {
    const allocator = std.heap.page_allocator;

    var file_ctx = Context{ .ignore_list = .{} };

    var pool = Pool{};
    try pool.init(.{
        .allocator = allocator,
        .n_jobs = cfg.n_threads,
    });
    defer pool.deinit();

    var wg = WaitGroup.init();

    // Initialize stats tracker
    var stats = ProcessStats.init();

    var walker_ctx = WalkerCtx{
        .pool = &pool,
        .wg = &wg,
        .file_ctx = &file_ctx,
        .cache = cache,
        .stats = &stats,
        .allocator = allocator,
    };

    const walker = try walk.init(allocator);
    const walk_ctx: ?*Context = @ptrCast(@alignCast(&walker_ctx));

    try walker.walkDir(cfg.path, walkCallback, walk_ctx);

    // Wait for all jobs to complete
    wg.wait();

    // Print summary
    stats.printSummary();
}
