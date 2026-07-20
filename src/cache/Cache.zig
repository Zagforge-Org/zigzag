//! Cache implementation to cache temporary files

const std = @import("std");
const Entry = @import("Entry.zig");

const Self = @This();

allocator: std.mem.Allocator,
io: std.Io,
cache_dir: []const u8,
files_dir: []const u8,
small_file_threshold: usize,
memory_cache: std.StringHashMap(Entry),
mutex: std.Io.Mutex,

/// Initializes the cache.
///
/// This function has side effects:
/// - Creates the `.cache` directory if it does not already exist.
/// - Duplicates `cache_dir` so the `Cache` owns its own copy instead of
///   borrowing the caller's memory.
pub fn init(allocator: std.mem.Allocator, io: std.Io, cache_dir: []const u8, small_file_threshold: usize) !Self {
    const cwd = std.Io.Dir.cwd();

    // Create .cache directory if one does not already exist.
    cwd.createDir(io, cache_dir, .default_dir) catch |err| {
        switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        }
    };

    // Create .cache/files directory if one does not already exist.
    const files_dir = try std.fmt.allocPrint(allocator, "{s}/files", .{cache_dir});
    cwd.createDir(io, files_dir, .default_dir) catch |err| {
        switch (err) {
            error.PathAlreadyExists => {},
            else => {
                allocator.free(files_dir);
                return err;
            },
        }
    };

    const owned_cache_dir = try allocator.dupe(u8, cache_dir);

    var cache = Self{
        .allocator = allocator,
        .cache_dir = owned_cache_dir,
        .files_dir = files_dir,
        .small_file_threshold = small_file_threshold,
        .memory_cache = std.StringHashMap(Entry).init(allocator),
        .io = io,
        .mutex = .init,
    };

    try cache.loadFromDisk();
    try cache.validateCache();
    return cache;
}

/// Validates cached entries against the current filesystem state.
///
/// An entry is considered invalid if:
/// - The file no longer exists.
/// - The file's modification time (`mtime`) has changed.
/// - The file's size has changed.
///
/// Invalid entries are removed from the in-memory cache and their
/// corresponding cached files are deleted from disk.
fn validateCache(self: *Self) !void {
    var invalid_entries: std.ArrayList([]const u8) = .empty;

    // Free all `invalid_entries` to prevent memory leaks.
    defer {
        for (invalid_entries.items) |path| {
            self.allocator.free(path);
        }

        invalid_entries.deinit(self.allocator);
    }

    var it = self.memory_cache.iterator();

    while (it.next()) |entry| {
        const path = entry.key_ptr.*;

        const stat = std.Io.Dir.cwd().statFile(self.io, path, .{ .follow_symlinks = true }) catch |err| switch (err) {
            error.FileNotFound => {
                // Mark file for removal
                const path_dupe = try self.allocator.dupe(u8, path);
                try invalid_entries.append(self.allocator, path_dupe);
                continue;
            },
            else => {
                return err;
            },
        };

        const mtime: u64 = @intCast(@divFloor(stat.mtime.nanoseconds, std.time.ns_per_s));
        const size = stat.size;

        // If the file was modified, mark it for removal.
        if (entry.value_ptr.mtime != mtime or entry.value_ptr.size != size) {
            const path_dupe = try self.allocator.dupe(u8, path);
            try invalid_entries.append(self.allocator, path_dupe);
        }
    }

    // Remove invalid entries
    for (invalid_entries.items) |path| {
        if (self.memory_cache.fetchRemove(path)) |kv| {
            std.log.debug("Invalidating cache for: {s}", .{path});

            const cached_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{
                self.files_dir,
                kv.value.cache_filename,
            });

            defer self.allocator.free(cached_path);
            std.Io.Dir.cwd().deleteFile(self.io, cached_path) catch {
                std.log.debug("Failed to delete file: {s}", .{cached_path});
            };

            self.allocator.free(kv.key);
            self.allocator.free(kv.value.cache_filename);
        }
    }

    if (invalid_entries.items.len > 0) {
        std.log.debug("Invalidated {d} stale cache entries", .{invalid_entries.items.len});
    }
}

/// Loads the cache index from disk into memory.
///
/// The cache index contains serialized cache entries in the format:
/// `path|mtime|size|cache_filename`.
///
/// Each valid entry is parsed and inserted into `memory_cache`.
/// Paths and cache filenames are duplicated because `memory_cache` owns
/// the allocated memory for its entries.
fn loadFromDisk(self: *Self) !void {
    const cache_index_path = try std.fmt.allocPrint(self.allocator, "{s}/index", .{self.cache_dir});
    defer self.allocator.free(cache_index_path);

    const data = std.Io.Dir.cwd().readFileAlloc(self.io, cache_index_path, self.allocator, .unlimited) catch |err| {
        if (err == error.FileNotFound) return;
        return err;
    };

    defer self.allocator.free(data);

    if (data.len == 0) return;

    var lines = std.mem.splitSequence(u8, data, "\n");

    while (lines.next()) |line| {
        if (line.len == 0) continue;

        // path|mtime|size|cache_filename
        var parts = std.mem.splitSequence(u8, line, "|");
        const path = parts.next() orelse continue;
        const mtime_str = parts.next() orelse continue;
        const size_str = parts.next() orelse continue;
        const cache_filename = parts.next() orelse continue;

        const mtime = std.fmt.parseInt(u64, mtime_str, 10) catch continue;
        const size = std.fmt.parseInt(usize, size_str, 10) catch continue;

        const path_dupe = try self.allocator.dupe(u8, path);
        const filename_dupe = try self.allocator.dupe(u8, cache_filename);

        try self.memory_cache.put(path_dupe, .{
            .mtime = mtime,
            .size = size,
            .cache_filename = filename_dupe,
        });
    }
}

/// Saves the in-memory cache index to disk.
///
/// The index is first written to a temporary `.tmp` file and then renamed
/// over the existing index to avoid leaving a partially written cache file
/// if the write fails.
///
/// Each entry is serialized as:
/// `path|mtime|size|cache_filename`
pub fn saveToDisk(self: *Self) !void {
    const cache_index_path = try std.fmt.allocPrint(self.allocator, "{s}/index", .{self.cache_dir});
    defer self.allocator.free(cache_index_path);

    const temp_path = try std.fmt.allocPrint(self.allocator, "{s}.tmp", .{cache_index_path});
    defer self.allocator.free(temp_path);

    var file = try std.Io.Dir.cwd().createFile(self.io, temp_path, .{ .truncate = true });
    defer file.close(self.io);

    // Assemble the whole index in memory and write it once; a syscall per entry
    // is measurably slow with tens of thousands of entries.
    var aw: std.Io.Writer.Allocating = .init(self.allocator);
    defer aw.deinit();

    var it = self.memory_cache.iterator();
    while (it.next()) |entry| {
        try aw.writer.print("{s}|{d}|{d}|{s}\n", .{
            entry.key_ptr.*,
            entry.value_ptr.mtime,
            entry.value_ptr.size,
            entry.value_ptr.cache_filename,
        });
    }
    try file.writeStreamingAll(self.io, aw.written());

    try std.Io.Dir.cwd().rename(temp_path, std.Io.Dir.cwd(), cache_index_path, self.io);
}

/// Generates a filesystem-safe cache filename from a path.
/// The filename contains a sanitized portion of the original path for
/// readability and a hash suffix to avoid collisions between paths.
fn pathToFilename(self: *Self, path: []const u8) ![]u8 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(path);

    const hash = hasher.final();

    var sanitized: std.ArrayList(u8) = .empty;
    defer sanitized.deinit(self.allocator);

    const max_path_len = 128;
    const path_to_use = if (path.len > max_path_len) path[path.len - max_path_len ..] else path;

    for (path_to_use) |c| {
        const safe_c = switch (c) {
            '/', '\\', ':', '*', '?', '"', '<', '>', '|', ' ' => '_',
            else => c,
        };
        try sanitized.append(self.allocator, safe_c);
    }

    return std.fmt.allocPrint(self.allocator, "{s}_{x}", .{ sanitized.items, hash });
}

/// Checks whether a file is present in the cache and still valid.
///
/// An entry is considered cached only if:
/// - It exists in `memory_cache`.
/// - The corresponding cached file exists on disk.
/// - The file's modification time and size match the cached metadata.
pub fn isCached(self: *Self, path: []const u8, mtime: u64, size: usize, _: ?[32]u8) !bool {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);

    const entry = self.memory_cache.get(path) orelse return false;

    const cached_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{
        self.files_dir,
        entry.cache_filename,
    });
    defer self.allocator.free(cached_path);

    std.Io.Dir.cwd().access(self.io, cached_path, .{}) catch {
        std.log.debug("Cache file missing for {s}, invalidating", .{path});
        return false;
    };

    return entry.mtime == mtime and entry.size == size;
}

/// Retrieves cached file content for a given path.
///
/// The cache index lookup is protected by a mutex to allow safe concurrent
/// access to `memory_cache`. The lock is released before reading the cache
/// file from disk to avoid holding the lock during I/O.
pub fn getCachedContent(self: *Self, path: []const u8) ![]u8 {
    self.mutex.lockUncancelable(self.io);

    const entry = self.memory_cache.get(path) orelse {
        self.mutex.unlock(self.io);
        return error.NotCached;
    };
    const cache_filename = entry.cache_filename;
    self.mutex.unlock(self.io);

    const cached_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{
        self.files_dir,
        cache_filename,
    });
    defer self.allocator.free(cached_path);

    const content = std.Io.Dir.cwd().readFileAlloc(self.io, cached_path, self.allocator, .unlimited) catch |err| {
        std.log.err("Cache file exists in index but failed to read {s}: {}", .{ cached_path, err });
        return err;
    };

    std.log.debug("Successfully read {d} bytes from cache: {s}", .{ content.len, cache_filename });
    return content;
}

/// Updates or creates a cache entry for a file.
///
/// Existing entries have their metadata updated and their cached content
/// overwritten. New entries generate a cache filename, store the entry in
/// `memory_cache`, and write the content to disk.
///
/// If writing the cache file fails, newly created entries are removed from
/// `memory_cache` to avoid leaving stale index entries.
pub fn update(self: *Self, path: []const u8, _: ?[32]u8, mtime: u64, size: usize, content: []const u8) !void {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);

    // Get or create cache filename
    var cache_filename: []u8 = undefined;
    var need_to_free_filename = false;
    var is_new_entry = false;

    if (self.memory_cache.getPtr(path)) |entry_ptr| {
        // Update existing entry
        cache_filename = entry_ptr.cache_filename;
        entry_ptr.mtime = mtime;
        entry_ptr.size = size;
    } else {
        // New entry generate filename
        cache_filename = try self.pathToFilename(path);
        need_to_free_filename = true;
        is_new_entry = true;

        const path_copy = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(path_copy);

        try self.memory_cache.put(path_copy, .{
            .mtime = mtime,
            .size = size,
            .cache_filename = cache_filename,
        });
        need_to_free_filename = false; // Now owned by hashmap
    }

    // Write content to cache file
    const cached_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{
        self.files_dir,
        cache_filename,
    });
    defer self.allocator.free(cached_path);

    // Ensure we can write the file
    var file = std.Io.Dir.cwd().createFile(self.io, cached_path, .{ .truncate = true }) catch |err| {
        std.log.err("Failed to create cache file {s}: {}", .{ cached_path, err });

        // If we just added this entry, remove it from the cache
        if (is_new_entry) {
            if (self.memory_cache.fetchRemove(path)) |kv| {
                self.allocator.free(kv.key);
                self.allocator.free(kv.value.cache_filename);
            }
        }
        return err;
    };
    defer file.close(self.io);

    file.writeStreamingAll(self.io, content) catch |err| {
        std.log.err("Failed to write cache file {s}: {}", .{ cached_path, err });

        // Clean up the partial file
        std.Io.Dir.cwd().deleteFile(self.io, cached_path) catch {};

        // If we just added this entry, remove it from the cache
        if (is_new_entry) {
            if (self.memory_cache.fetchRemove(path)) |kv| {
                self.allocator.free(kv.key);
                self.allocator.free(kv.value.cache_filename);
            }
        }
        return err;
    };

    if (is_new_entry) {
        std.log.debug("Cached new file: {s} -> {s}", .{ path, cache_filename });
    } else {
        std.log.debug("Updated cache for: {s}", .{path});
    }

    if (need_to_free_filename) {
        self.allocator.free(cache_filename);
    }
}

pub fn entryCount(self: *const Self) usize {
    return self.memory_cache.count();
}

pub fn hashFileContent(self: *Self, path: []const u8) ![32]u8 {
    _ = self;
    _ = path;
    return [_]u8{0} ** 32;
}

/// Cleans up the cache by releasing allocated memory and deleting cached files.
///
/// This frees all owned strings stored in `memory_cache`, clears the in-memory
/// index, and removes all files stored in the cache directory.
pub fn cleanup(self: *Self) !void {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);

    // Free memory cache
    var it = self.memory_cache.iterator();
    while (it.next()) |entry| {
        self.allocator.free(entry.key_ptr.*);
        self.allocator.free(entry.value_ptr.cache_filename);
    }
    self.memory_cache.clearAndFree();

    // Delete all cache files
    var dir = try std.Io.Dir.cwd().openDir(self.io, self.cache_dir, .{ .iterate = true });
    defer dir.close(self.io);

    var dir_it = dir.iterate();
    while (try dir_it.next(self.io)) |entry| {
        if (entry.kind == .directory) {
            var subdir = try dir.openDir(self.io, entry.name, .{ .iterate = true });
            defer subdir.close(self.io);

            var subdir_it = subdir.iterate();
            while (try subdir_it.next(self.io)) |subentry| {
                subdir.deleteFile(self.io, subentry.name) catch {};
            }
        } else {
            dir.deleteFile(self.io, entry.name) catch {};
        }
    }
}

pub fn deinit(self: *Self) void {
    self.saveToDisk() catch |err| {
        std.log.err("Failed to save cache to disk: {}", .{err});
    };

    // Verify cache consistency before shutting down
    self.verifyCacheConsistency() catch |err| {
        std.log.warn("Cache consistency check failed: {}", .{err});
    };

    var it = self.memory_cache.iterator();
    while (it.next()) |entry| {
        self.allocator.free(entry.key_ptr.*);
        self.allocator.free(entry.value_ptr.cache_filename);
    }
    self.memory_cache.deinit();
    self.allocator.free(self.cache_dir);
    self.allocator.free(self.files_dir);
}

/// verifyCacheConsistency verifies the cache consistency by
/// checking that all index entries have corresponding files.
fn verifyCacheConsistency(self: *Self) !void {
    var missing_count: usize = 0;

    var it = self.memory_cache.iterator();
    while (it.next()) |entry| {
        const cached_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{
            self.files_dir,
            entry.value_ptr.cache_filename,
        });
        defer self.allocator.free(cached_path);

        std.Io.Dir.cwd().access(self.io, cached_path, .{}) catch {
            std.log.warn("Cache inconsistency: index has {s} but file {s} is missing", .{
                entry.key_ptr.*,
                entry.value_ptr.cache_filename,
            });
            missing_count += 1;
        };
    }

    if (missing_count > 0) {
        std.log.warn("Cache has {d} missing files out of {d} total entries", .{
            missing_count,
            self.memory_cache.count(),
        });
    }
}
