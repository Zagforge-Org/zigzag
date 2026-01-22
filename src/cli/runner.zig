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

// Structure to hold both the path and context - path is owned and will be freed
const FileJob = struct {
    path: []const u8,
    ctx: ?*Context,
    cache: *FileCache,
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

    if (ctx) |c| {
        if (shouldIgnore(path, c.ignore_list)) {
            std.log.debug("Ignoring file: {s}", .{path});
            return;
        }
    }

    const allocator = std.heap.page_allocator;

    // Get file metadata
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        std.log.err("Failed to open file {s}: {}", .{ path, err });
        return err;
    };
    defer file.close();

    const stat = try file.stat();
    const mtime = @as(u64, @intCast(stat.mtime));
    const size = stat.size;

    // Determine if we need to hash (large file)
    const small_file_threshold = cache.small_file_threshold;
    var hash: ?[32]u8 = null;

    if (size > small_file_threshold) {
        // Large file - compute hash
        hash = try cache.hashFileContent(path);
    }

    // Check if file is cached
    const is_cached = cache.isCached(path, mtime, size, hash) catch false;

    if (is_cached) {
        std.log.debug("File cached, skipping: {s}", .{path});
        return;
    }

    std.log.debug("Processing file: {s}", .{path});

    // Process the file
    var result = try fs.readFileAuto(allocator, path, processChunk);
    switch (result) {
        .Alloc => |data| {
            defer allocator.free(data);
            std.log.debug("Processed allocated file: {s}", .{path});
        },
        .Mapped => |*mapped| {
            defer mapped.deinit();
            std.log.debug("Processed mapped file: {s}", .{path});
        },
        .Chunked => {
            std.log.debug("Processed chunked file: {s}", .{path});
        },
    }

    // Update cache after successful processing
    try cache.update(path, hash, mtime, size);
}

/// Context for the walker, passing pool + waitgroup + file context + allocator + cache
const WalkerCtx = struct {
    pool: *Pool,
    wg: *WaitGroup,
    file_ctx: *Context,
    cache: *FileCache,
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

    var walker_ctx = WalkerCtx{
        .pool = &pool,
        .wg = &wg,
        .file_ctx = &file_ctx,
        .cache = cache,
        .allocator = allocator,
    };

    const walker = try walk.init(allocator);
    const walk_ctx: ?*Context = @ptrCast(@alignCast(&walker_ctx));

    try walker.walkDir(cfg.path, walkCallback, walk_ctx);

    // Wait for all jobs to complete
    wg.wait();

    std.log.info("All files processed", .{});
}
