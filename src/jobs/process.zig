const std = @import("std");
const Job = @import("job.zig").Job;
const fs = @import("../fs/file.zig");

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

pub fn processFileJob(job: Job) anyerror!void {
    defer {
        var mutable_job = job;
        mutable_job.deinit();
    }

    const path = job.path;
    const file_ctx = job.file_ctx;
    const cache = job.cache;
    const stats = job.stats;
    const file_entries = job.file_entries;
    const entries_mutex = job.entries_mutex;

    if (file_ctx) |ctx| {
        if (shouldIgnore(path, ctx.ignore_list)) {
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
