const std = @import("std");

/// CacheEntry represents an entry in the file cache.
const CacheEntry = struct {
    mtime: u64,
    size: usize,
};

pub const FileCache = struct {
    allocator: std.mem.Allocator,
    cache_dir: []const u8,
    small_file_threshold: usize,
    // In-memory cache to avoid disk I/O
    memory_cache: std.StringHashMap(CacheEntry),
    mutex: std.Thread.Mutex,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, cache_dir: []const u8, small_file_threshold: usize) !Self {
        // Ensure cache directory exists
        const cwd = std.fs.cwd();
        cwd.makeDir(cache_dir) catch |err| {
            switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            }
        };

        const owned_dir = try allocator.dupe(u8, cache_dir);

        var cache = Self{
            .allocator = allocator,
            .cache_dir = owned_dir,
            .small_file_threshold = small_file_threshold,
            .memory_cache = std.StringHashMap(CacheEntry).init(allocator),
            .mutex = .{},
        };

        // Load existing cache from disk into memory
        try cache.loadFromDisk();

        return cache;
    }

    /// Load cache entries from disk into memory
    fn loadFromDisk(self: *Self) !void {
        const cache_index_path = try std.fmt.allocPrint(self.allocator, "{s}/index", .{self.cache_dir});
        defer self.allocator.free(cache_index_path);

        const file = std.fs.cwd().openFile(cache_index_path, .{}) catch |err| {
            // No cache file exists yet, that's fine
            if (err == error.FileNotFound) return;
            return err;
        };
        defer file.close();

        const data = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024); // 10MB max
        defer self.allocator.free(data);

        var lines = std.mem.splitSequence(u8, data, "\n");
        while (lines.next()) |line| {
            if (line.len == 0) continue;

            // Format: path|mtime|size
            var parts = std.mem.splitSequence(u8, line, "|");
            const path = parts.next() orelse continue;
            const mtime_str = parts.next() orelse continue;
            const size_str = parts.next() orelse continue;

            const mtime = std.fmt.parseInt(u64, mtime_str, 10) catch continue;
            const size = std.fmt.parseInt(usize, size_str, 10) catch continue;

            const path_copy = try self.allocator.dupe(u8, path);
            try self.memory_cache.put(path_copy, .{ .mtime = mtime, .size = size });
        }
    }

    /// Save cache entries from memory to disk
    fn saveToDisk(self: *Self) !void {
        const cache_index_path = try std.fmt.allocPrint(self.allocator, "{s}/index", .{self.cache_dir});
        defer self.allocator.free(cache_index_path);

        var file = try std.fs.cwd().createFile(cache_index_path, .{ .truncate = true });
        defer file.close();

        var it = self.memory_cache.iterator();
        while (it.next()) |entry| {
            const line = try std.fmt.allocPrint(self.allocator, "{s}|{d}|{d}\n", .{
                entry.key_ptr.*,
                entry.value_ptr.mtime,
                entry.value_ptr.size,
            });
            defer self.allocator.free(line);
            try file.writeAll(line);
        }
    }

    /// Check if file is cached (in-memory lookup, very fast)
    pub fn isCached(self: *Self, path: []const u8, mtime: u64, size: usize, _: ?[32]u8) !bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        const entry = self.memory_cache.get(path) orelse return false;
        return entry.mtime == mtime and entry.size == size;
    }

    /// Update cache for a file (in-memory, batched to disk later)
    pub fn update(self: *Self, path: []const u8, _: ?[32]u8, mtime: u64, size: usize) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check if we need to allocate a new path
        if (self.memory_cache.get(path)) |_| {
            // Path already exists, just update the entry
            try self.memory_cache.put(path, .{ .mtime = mtime, .size = size });
        } else {
            // New path, need to allocate
            const path_copy = try self.allocator.dupe(u8, path);
            try self.memory_cache.put(path_copy, .{ .mtime = mtime, .size = size });
        }
    }

    /// Cleanup stale entries
    pub fn cleanup(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Clear memory cache
        var it = self.memory_cache.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.memory_cache.clearAndFree();

        // Delete cache index file
        const cache_index_path = try std.fmt.allocPrint(self.allocator, "{s}/index", .{self.cache_dir});
        defer self.allocator.free(cache_index_path);
        std.fs.cwd().deleteFile(cache_index_path) catch {};
    }

    /// Hash large file content (simplified - just use mtime+size)
    /// This is much faster than computing SHA-256
    pub fn hashFileContent(self: *Self, path: []const u8) ![32]u8 {
        _ = self;
        _ = path;
        // For this optimized version, we don't actually hash
        // We rely on mtime+size which is already checked
        return [_]u8{0} ** 32;
    }

    pub fn deinit(self: *Self) void {
        // Save cache to disk before cleanup
        self.saveToDisk() catch {};

        // Free all path strings
        var it = self.memory_cache.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.memory_cache.deinit();
        self.allocator.free(self.cache_dir);
    }
};
