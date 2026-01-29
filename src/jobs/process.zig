const std = @import("std");
const Job = @import("job.zig").Job;
const fs = @import("../fs/file.zig");

fn basename(path: []const u8) []const u8 {
    var lastSlash: usize = 0;
    var i: usize = 0;
    while (i < path.len) : (i += 1) {
        if (path[i] == '/' or path[i] == '\\') lastSlash = i + 1;
    }
    return path[lastSlash..];
}

fn getExtension(path: []const u8) []const u8 {
    const name = basename(path);
    var i: usize = name.len;
    while (i > 0) {
        i -= 1;
        if (name[i] == '.') {
            return name[i..];
        }
    }
    return "";
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
    const cache_opt = job.cache; // ?*CacheImpl
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

    // Check if file still exists
    const stat = std.fs.cwd().statFile(path) catch |err| {
        if (err == error.FileNotFound) {
            std.log.debug(
                "File not found (may have been moved/deleted): {s}",
                .{path},
            );
            _ = stats.ignored_files.fetchAdd(1, .monotonic);
        } else {
            std.log.debug(
                "Failed to stat file {s}: {}",
                .{ path, err },
            );
        }
        return;
    };

    const mtime = stat.mtime;
    const size = stat.size;

    // Skip empty files
    if (size == 0) {
        std.log.debug("Skipping empty file: {s}", .{path});
        _ = stats.ignored_files.fetchAdd(1, .monotonic);
        return;
    }

    const mtime_seconds: u64 =
        @intCast(@divFloor(mtime, std.time.ns_per_s));

    var hash: ?[32]u8 = null;
    var content: []u8 = undefined;

    // =========================
    // CACHE MODE
    // =========================
    if (cache_opt) |cache| {
        const small_file_threshold = cache.small_file_threshold;

        if (size > small_file_threshold) {
            hash = cache.hashFileContent(path) catch |err| {
                std.log.debug(
                    "Failed to hash file {s}: {}",
                    .{ path, err },
                );
                return;
            };
        }

        const is_cached =
            cache.isCached(path, mtime_seconds, size, hash) catch false;

        if (is_cached) {
            std.log.debug(
                "Cached (reading from .cache): {s}",
                .{path},
            );

            _ = stats.cached_files.fetchAdd(1, .monotonic);

            content = cache.getCachedContent(path) catch blk: {
                std.log.warn(
                    "Cache hit but failed for {s}, reading original",
                    .{path},
                );

                _ = stats.cached_files.fetchSub(1, .monotonic);
                _ = stats.processed_files.fetchAdd(1, .monotonic);

                const original =
                    fs.readFileAlloc(allocator, path) catch |read_err| {
                        std.log.err(
                            "Failed to read {s}: {}",
                            .{ path, read_err },
                        );
                        return;
                    };

                cache.update(
                    path,
                    hash,
                    mtime_seconds,
                    size,
                    original,
                ) catch {};

                break :blk original;
            };
        } else {
            std.log.info(
                "Processing (reading original): {s}",
                .{path},
            );

            _ = stats.processed_files.fetchAdd(1, .monotonic);

            content =
                fs.readFileAlloc(allocator, path) catch |err| {
                    std.log.debug(
                        "Failed to read {s}: {}",
                        .{ path, err },
                    );
                    _ = stats.processed_files.fetchSub(1, .monotonic);
                    _ = stats.ignored_files.fetchAdd(1, .monotonic);
                    return;
                };

            cache.update(
                path,
                hash,
                mtime_seconds,
                size,
                content,
            ) catch |err| {
                std.log.err(
                    "Cache update failed for {s}: {}",
                    .{ path, err },
                );
            };
        }
    }
    // =========================
    // NO CACHE MODE
    // =========================
    else {
        std.log.info(
            "Processing (no cache): {s}",
            .{path},
        );

        _ = stats.processed_files.fetchAdd(1, .monotonic);

        content =
            fs.readFileAlloc(allocator, path) catch |err| {
                std.log.debug(
                    "Failed to read {s}: {}",
                    .{ path, err },
                );
                _ = stats.processed_files.fetchSub(1, .monotonic);
                _ = stats.ignored_files.fetchAdd(1, .monotonic);
                return;
            };
    }

    // =========================
    // Store result
    // =========================
    entries_mutex.lock();
    defer entries_mutex.unlock();

    const path_copy = try allocator.dupe(u8, path);
    const extension = getExtension(path);
    const ext_copy = try allocator.dupe(u8, extension);

    try file_entries.put(path_copy, .{
        .path = path_copy,
        .content = content,
        .size = size,
        .mtime = mtime,
        .extension = ext_copy,
    });
}
