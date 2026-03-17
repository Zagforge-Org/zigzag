const std = @import("std");
const Job = @import("job.zig").Job;
const BinaryEntry = @import("entry.zig").BinaryEntry;
const fs = @import("../fs/file.zig");
const DEFAULT_SKIP_DIRS = @import("../utils/utils.zig").DEFAULT_SKIP_DIRS;

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
        ".bz2", ".lz4", ".lzma",  ".xz",    ".zst", ".zstd",
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
    for (DEFAULT_SKIP_DIRS) |pattern| {
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

/// Count lines in a content buffer.
/// Each '\n' counts as a line separator; if the content doesn't end with '\n',
/// the last partial line is still counted.
fn countLines(content: []const u8) usize {
    if (content.len == 0) return 0;
    var count: usize = 0;
    for (content) |c| {
        if (c == '\n') count += 1;
    }
    if (content[content.len - 1] != '\n') count += 1;
    return count;
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
    const binary_entries = job.binary_entries;
    const entries_mutex = job.entries_mutex;

    if (file_ctx) |ctx| {
        if (shouldIgnore(path, ctx.ignore_list)) {
            _ = stats.ignored_files.fetchAdd(1, .monotonic);
            return;
        }
    }

    const allocator = job.allocator;

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
    // Tracks whether the file was counted in cached_files (true) or processed_files (false).
    // Used by the binary-detection block below to subtract from the correct counter.
    var counted_as_cached = false;

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
            counted_as_cached = true;

            content = cache.getCachedContent(path) catch blk: {
                std.log.warn(
                    "Cache hit but failed for {s}, reading original",
                    .{path},
                );
                _ = stats.cached_files.fetchSub(1, .monotonic);
                counted_as_cached = false;
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
            std.log.debug(
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
        std.log.debug(
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
    const extension = getExtension(path);

    if (isBinaryFile(path, content)) {
        std.log.debug("Skipping binary file: {s}", .{path});
        allocator.free(content);
        _ = stats.binary_files.fetchAdd(1, .monotonic);
        // Subtract from the counter that was actually incremented above.
        // Cached files were counted in cached_files; all others in processed_files.
        if (counted_as_cached) {
            _ = stats.cached_files.fetchSub(1, .monotonic);
        } else {
            _ = stats.processed_files.fetchSub(1, .monotonic);
        }

        entries_mutex.lock();
        defer entries_mutex.unlock();

        const path_copy = try allocator.dupe(u8, path);
        const ext_copy = try allocator.dupe(u8, extension);
        try binary_entries.put(path_copy, .{
            .path = path_copy,
            .size = size,
            .mtime = mtime,
            .extension = ext_copy,
        });
        return;
    }

    // =========================
    // Line count
    // =========================
    const line_count = countLines(content);

    // =========================
    // Store result
    // =========================
    entries_mutex.lock();
    defer entries_mutex.unlock();

    const path_copy = try allocator.dupe(u8, path);
    const ext_copy = try allocator.dupe(u8, extension);

    try file_entries.put(path_copy, .{
        .path = path_copy,
        .content = content,
        .size = size,
        .mtime = mtime,
        .extension = ext_copy,
        .line_count = line_count,
    });
}

test "countLines returns 0 for empty content" {
    try std.testing.expectEqual(@as(usize, 0), countLines(""));
}

test "countLines counts a single line with no trailing newline" {
    try std.testing.expectEqual(@as(usize, 1), countLines("hello"));
}

test "countLines counts a single line with trailing newline" {
    try std.testing.expectEqual(@as(usize, 1), countLines("hello\n"));
}

test "countLines counts multiple lines with trailing newline" {
    try std.testing.expectEqual(@as(usize, 3), countLines("a\nb\nc\n"));
}

test "countLines counts multiple lines without trailing newline" {
    try std.testing.expectEqual(@as(usize, 3), countLines("a\nb\nc"));
}

test "isBinaryFile detects known binary extensions" {
    try std.testing.expect(isBinaryFile("logo.png", ""));
    try std.testing.expect(isBinaryFile("archive.zip", ""));
    try std.testing.expect(isBinaryFile("binary.exe", ""));
    try std.testing.expect(isBinaryFile("lib.so", ""));
}

test "isBinaryFile extension check is case-insensitive" {
    try std.testing.expect(isBinaryFile("logo.PNG", ""));
    try std.testing.expect(isBinaryFile("font.TTF", ""));
}

test "isBinaryFile returns false for text extensions" {
    try std.testing.expect(!isBinaryFile("main.zig", "const x = 1;"));
    try std.testing.expect(!isBinaryFile("script.py", "print('hi')"));
    try std.testing.expect(!isBinaryFile("README.md", "# Hello"));
}

test "isBinaryFile detects null bytes in content" {
    const content = "text\x00more";
    try std.testing.expect(isBinaryFile("unknown", content));
}

test "isBinaryFile detects high ratio of non-printable chars" {
    // Build a buffer where >30% of first 512 bytes are non-printable (control chars, not \n/\r/\t)
    var buf: [100]u8 = undefined;
    // 40 non-printable control chars (0x01) + 60 printable 'A' = 40% non-printable
    for (buf[0..40]) |*b| b.* = 0x01;
    for (buf[40..]) |*b| b.* = 'A';
    try std.testing.expect(isBinaryFile("data", &buf));
}

test "isBinaryFile returns false for low ratio of non-printable chars" {
    var buf: [100]u8 = undefined;
    // 10 control chars + 90 printable = 10% non-printable, below 30% threshold
    for (buf[0..10]) |*b| b.* = 0x01;
    for (buf[10..]) |*b| b.* = 'A';
    try std.testing.expect(!isBinaryFile("data", &buf));
}

test "isBinaryFile only examines first 512 bytes" {
    // First 512 bytes are clean text; byte 513+ has null byte — should NOT be detected
    var buf: [600]u8 = undefined;
    for (buf[0..512]) |*b| b.* = 'A';
    buf[512] = 0x00; // null byte beyond the check window
    try std.testing.expect(!isBinaryFile("data", &buf));
}
