const std = @import("std");
const CacheEntry = @import("entry.zig").CacheEntry;

pub const CacheImpl = struct {
    allocator: std.mem.Allocator,
    cache_dir: []const u8,
    files_dir: []const u8,
    small_file_threshold: usize,
    memory_cache: std.StringHashMap(CacheEntry),
    mutex: std.Thread.Mutex,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, cache_dir: []const u8, small_file_threshold: usize) !Self {
        const cwd = std.fs.cwd();

        // Create .cache directory
        cwd.makeDir(cache_dir) catch |err| {
            switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            }
        };

        // Create .cache/files directory
        const files_dir = try std.fmt.allocPrint(allocator, "{s}/files", .{cache_dir});
        cwd.makeDir(files_dir) catch |err| {
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
            .memory_cache = std.StringHashMap(CacheEntry).init(allocator),
            .mutex = .{},
        };

        try cache.loadFromDisk();
        return cache;
    }

    fn loadFromDisk(self: *Self) !void {
        const cache_index_path = try std.fmt.allocPrint(self.allocator, "{s}/index", .{self.cache_dir});
        defer self.allocator.free(cache_index_path);

        const file = std.fs.cwd().openFile(cache_index_path, .{}) catch |err| {
            if (err == error.FileNotFound) return;
            return err;
        };
        defer file.close();

        const data = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
        defer self.allocator.free(data);

        var lines = std.mem.splitSequence(u8, data, "\n");
        while (lines.next()) |line| {
            if (line.len == 0) continue;

            // Format: path|mtime|size|cache_filename
            var parts = std.mem.splitSequence(u8, line, "|");
            const path = parts.next() orelse continue;
            const mtime_str = parts.next() orelse continue;
            const size_str = parts.next() orelse continue;
            const cache_filename = parts.next() orelse continue;

            const mtime = std.fmt.parseInt(u64, mtime_str, 10) catch continue;
            const size = std.fmt.parseInt(usize, size_str, 10) catch continue;

            const path_copy = try self.allocator.dupe(u8, path);
            const filename_copy = try self.allocator.dupe(u8, cache_filename);

            try self.memory_cache.put(path_copy, .{
                .mtime = mtime,
                .size = size,
                .cache_filename = filename_copy,
            });
        }
    }

    fn saveToDisk(self: *Self) !void {
        const cache_index_path = try std.fmt.allocPrint(self.allocator, "{s}/index", .{self.cache_dir});
        defer self.allocator.free(cache_index_path);

        var file = try std.fs.cwd().createFile(cache_index_path, .{ .truncate = true });
        defer file.close();

        var it = self.memory_cache.iterator();
        while (it.next()) |entry| {
            const line = try std.fmt.allocPrint(self.allocator, "{s}|{d}|{d}|{s}\n", .{
                entry.key_ptr.*,
                entry.value_ptr.mtime,
                entry.value_ptr.size,
                entry.value_ptr.cache_filename,
            });
            defer self.allocator.free(line);
            try file.writeAll(line);
        }
    }

    /// Generate a safe filename from a path
    fn pathToFilename(self: *Self, path: []const u8) ![]u8 {
        var result = try self.allocator.alloc(u8, path.len);
        for (path, 0..) |c, i| {
            result[i] = switch (c) {
                '/', '\\', ':', '*', '?', '"', '<', '>', '|' => '_',
                else => c,
            };
        }
        return result;
    }

    pub fn isCached(self: *Self, path: []const u8, mtime: u64, size: usize, _: ?[32]u8) !bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        const entry = self.memory_cache.get(path) orelse return false;
        return entry.mtime == mtime and entry.size == size;
    }

    /// Get content from cache - returns owned slice that caller must free
    pub fn getCachedContent(self: *Self, path: []const u8) ![]u8 {
        self.mutex.lock();
        const entry = self.memory_cache.get(path) orelse {
            self.mutex.unlock();
            return error.NotCached;
        };
        const cache_filename = entry.cache_filename;
        self.mutex.unlock();

        const cached_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{
            self.files_dir,
            cache_filename,
        });
        defer self.allocator.free(cached_path);

        return try std.fs.cwd().readFileAlloc(self.allocator, cached_path, 100 * 1024 * 1024);
    }

    /// Update cache - copies file content to cache
    pub fn update(self: *Self, path: []const u8, _: ?[32]u8, mtime: u64, size: usize, content: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Get or create cache filename
        var cache_filename: []u8 = undefined;
        var need_to_free_filename = false;

        if (self.memory_cache.getPtr(path)) |entry_ptr| {
            // Update existing entry
            cache_filename = entry_ptr.cache_filename;
            entry_ptr.mtime = mtime;
            entry_ptr.size = size;
        } else {
            // New entry - generate filename
            cache_filename = try self.pathToFilename(path);
            need_to_free_filename = true;

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

        var file = try std.fs.cwd().createFile(cached_path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(content);

        if (need_to_free_filename) {
            self.allocator.free(cache_filename);
        }
    }

    pub fn cleanup(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Free memory cache
        var it = self.memory_cache.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.cache_filename);
        }
        self.memory_cache.clearAndFree();

        // Delete all cache files
        var dir = try std.fs.cwd().openDir(self.cache_dir, .{ .iterate = true });
        defer dir.close();

        var dir_it = dir.iterate();
        while (try dir_it.next()) |entry| {
            if (entry.kind == .directory) {
                var subdir = try dir.openDir(entry.name, .{ .iterate = true });
                defer subdir.close();

                var subdir_it = subdir.iterate();
                while (try subdir_it.next()) |subentry| {
                    subdir.deleteFile(subentry.name) catch {};
                }
            } else {
                dir.deleteFile(entry.name) catch {};
            }
        }
    }

    pub fn hashFileContent(self: *Self, path: []const u8) ![32]u8 {
        _ = self;
        _ = path;
        return [_]u8{0} ** 32;
    }

    pub fn deinit(self: *Self) void {
        self.saveToDisk() catch {};

        var it = self.memory_cache.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.cache_filename);
        }
        self.memory_cache.deinit();
        self.allocator.free(self.cache_dir);
        self.allocator.free(self.files_dir);
    }
};
