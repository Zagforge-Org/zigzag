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

fn processChunk(_: *Context, chunk: []const u8) void {
    // Process the chunk data here
    std.log.info("Processing chunk of size: {d} bytes", .{chunk.len});

    // Optional: Show preview of content
    const preview_len = @min(chunk.len, 50);
    std.log.debug("Preview: {s}", .{chunk[0..preview_len]});
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
        std.log.debug("Cached (skipping): {s}", .{path});
        _ = stats.cached_files.fetchAdd(1, .monotonic);
        return;
    }

    // File is new or changed, process it
    std.log.info("Processing: {s}", .{path});
    _ = stats.processed_files.fetchAdd(1, .monotonic);

    // Process the file
    // readFileAuto opens and closes its own file handle
    var result = fs.readFileAuto(allocator, path, processChunk, ctx.?) catch |err| {
        std.log.debug("Failed to process file {s}: {}", .{ path, err });
        return;
    };

    switch (result) {
        .Alloc => |data| {
            std.log.debug("Read {s} via allocation ({d} bytes)", .{ path, data.len });
            processChunk(ctx.?, data);
            defer allocator.free(data);
        },
        .Mapped => |*mapped| {
            std.log.debug("Read {s} via mmap ({d} bytes)", .{ path, mapped.len });
            processChunk(ctx.?, mapped.data);
            defer mapped.deinit();
        },
        .Chunked => {
            std.log.debug("Read {s} via chunking", .{path});
            // Already processed via chunks in readFileChunked
        },
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

    // Build Markdown path relative to cfg.path
    const md_path = try std.fs.path.join(allocator, &.{
        cfg.path,
        "report.md",
    });
    defer allocator.free(md_path);

    var md_file = try std.fs.cwd().createFile(md_path, .{
        .truncate = true,
    });
    defer md_file.close();

    var mutex = std.Thread.Mutex{};

    var file_ctx = Context{
        .ignore_list = .{},
        .md = &md_file,
        .md_mutex = &mutex,
    };
    defer file_ctx.ignore_list.deinit(allocator);

    // Ignore generated Markdown file
    const owned_md_path = try allocator.dupe(u8, md_path);
    try file_ctx.ignore_list.append(allocator, owned_md_path);

    // Initialize ignore list from config
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

    std.log.info("Config path: {s}", .{cfg.path});

    try walker.walkDir(cfg.path, walkCallback, walk_ctx);

    // Wait for all jobs to complete
    wg.wait();

    // Print summary
    stats.printSummary();
}
