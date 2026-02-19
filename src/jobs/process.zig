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

/// Check if a file is binary by examining its extension and/or content
fn isBinaryFile(path: []const u8, content: []const u8) bool {
    const ext = getExtension(path);

    // Common binary file extensions
    const binary_extensions = [_][]const u8{
        ".png", ".jpg", ".jpeg",  ".gif",   ".bmp", ".ico",  ".webp",
        ".pdf", ".zip", ".tar",   ".gz",    ".7z",  ".rar",  ".exe",
        ".dll", ".so",  ".dylib", ".bin",   ".dat", ".db",   ".sqlite",
        ".mp3", ".mp4", ".avi",   ".mov",   ".mkv", ".woff", ".woff2",
        ".ttf", ".otf", ".eot",   ".class", ".jar", ".war",  ".o",
        ".a",   ".lib", ".pyc",   ".pyo",
    };

    // Check extension first (faster)
    for (binary_extensions) |binary_ext| {
        if (std.ascii.eqlIgnoreCase(ext, binary_ext)) {
            return true;
        }
    }

    // Heuristic: check for null bytes or high ratio of non-printable characters
    // Only check first 512 bytes for performance
    const check_len = @min(content.len, 512);
    var non_printable: usize = 0;

    for (content[0..check_len]) |byte| {
        if (byte == 0) return true; // Null byte = binary
        if (byte < 32 and byte != '\n' and byte != '\r' and byte != '\t') {
            non_printable += 1;
        }
    }

    // If more than 30% non-printable, consider it binary
    if (check_len > 0 and (non_printable * 100 / check_len) > 30) {
        return true;
    }

    return false;
}

/// Improved pattern matching for ignore patterns
fn matchesPattern(path: []const u8, pattern: []const u8) bool {
    const filename = basename(path);

    // Wildcard extension pattern: *.ext
    if (pattern.len >= 2 and pattern[0] == '*' and pattern[1] == '.') {
        const ext = getExtension(filename);
        return std.ascii.eqlIgnoreCase(ext, pattern[1..]);
    }

    // Wildcard prefix pattern: prefix*
    if (pattern.len >= 2 and pattern[pattern.len - 1] == '*') {
        const prefix = pattern[0 .. pattern.len - 1];
        return std.mem.startsWith(u8, filename, prefix);
    }

    // Wildcard suffix pattern: *suffix
    if (pattern.len >= 2 and pattern[0] == '*') {
        const suffix = pattern[1..];
        return std.mem.endsWith(u8, filename, suffix);
    }

    // Exact filename match
    if (std.mem.eql(u8, filename, pattern)) {
        return true;
    }

    // Path contains pattern (for directories like node_modules, .cache, etc.)
    if (std.mem.indexOf(u8, path, pattern) != null) {
        return true;
    }

    return false;
}

fn shouldIgnore(file: []const u8, ignore_list: std.ArrayList([]const u8)) bool {
    // Always ignore .cache directory
    if (std.mem.indexOf(u8, file, ".cache") != null) return true;

    // Always ignore common binary/hidden/build directories
    const auto_ignore = [_][]const u8{
        "node_modules",
        ".git",
        ".svn",
        ".hg",
        "__pycache__",
        ".pytest_cache",
        "target",
        "build",
        "dist",
        ".idea",
        ".vscode",
        ".DS_Store",
    };

    for (auto_ignore) |pattern| {
        if (std.mem.indexOf(u8, file, pattern) != null) {
            return true;
        }
    }

    // Check user-provided ignore patterns
    for (ignore_list.items) |pattern| {
        if (matchesPattern(file, pattern)) {
            return true;
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
    const cache_opt = job.cache;
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

    const mtime_seconds: u64 = @intCast(@divFloor(mtime, std.time.ns_per_s));
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

        const is_cached = cache.isCached(path, mtime_seconds, size, hash) catch false;

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

                const original = fs.readFileAlloc(allocator, path) catch |read_err| {
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

            content = fs.readFileAlloc(allocator, path) catch |err| {
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

        content = fs.readFileAlloc(allocator, path) catch |err| {
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
    // Binary file detection
    // =========================
    if (isBinaryFile(path, content)) {
        std.log.info("Skipping binary file: {s}", .{path});
        allocator.free(content);
        _ = stats.ignored_files.fetchAdd(1, .monotonic);
        // Adjust stats - we counted it as processed, but it's actually ignored
        _ = stats.processed_files.fetchSub(1, .monotonic);
        return;
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
