const std = @import("std");

const SEED: u64 = 0x123456789ABCDEF0;

/// CacheEntry represents an entry in the file cache.
/// We use extern struct to ensure the layout matches the C struct.
const CacheEntry = extern struct {
    path_len: u32,
    mtime: u64,
    size: usize,
    hash: [32]u8,
};

pub const FileCache = struct {
    allocator: std.mem.Allocator,
    cache_dir: []const u8,
    small_file_threshold: usize,
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

        // Duplicate the cache_dir string so we own it
        const owned_dir = try allocator.dupe(u8, cache_dir);

        return Self{
            .allocator = allocator,
            .cache_dir = owned_dir,
            .small_file_threshold = small_file_threshold,
            .mutex = .{},
        };
    }

    /// Compute cache file path
    fn computeCacheFilePath(self: *Self, path: []const u8, hash: ?[32]u8) ![]u8 {
        const allocator = self.allocator;
        if (hash) |h| {
            // Convert hash to hex string manually
            var hex_buf: [64]u8 = undefined;
            const charset = "0123456789abcdef";
            for (h, 0..) |byte, i| {
                hex_buf[i * 2] = charset[byte >> 4];
                hex_buf[i * 2 + 1] = charset[byte & 0x0F];
            }

            // Combine cache_dir and hex
            return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ self.cache_dir, hex_buf });
        } else {
            // Small file fast path - sanitize path
            const sanitized = try allocator.alloc(u8, path.len);
            defer allocator.free(sanitized);

            for (path, 0..) |c, i| {
                sanitized[i] = if (c == '/') '_' else c;
            }

            return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ self.cache_dir, sanitized });
        }
    }

    /// Check if file is cached
    pub fn isCached(self: *Self, path: []const u8, mtime: u64, size: usize, hash: ?[32]u8) !bool {
        const allocator = self.allocator;
        const cache_file = try self.computeCacheFilePath(path, hash);
        defer allocator.free(cache_file);

        self.mutex.lock();
        defer self.mutex.unlock();

        const file = std.fs.cwd().openFile(cache_file, .{ .mode = .read_only }) catch |err| {
            switch (err) {
                error.FileNotFound => return false,
                else => return err,
            }
        };
        defer file.close();

        const data = try file.readToEndAlloc(allocator, 8192);
        defer allocator.free(data);

        if (data.len < @sizeOf(CacheEntry)) return false;

        const entry: *const CacheEntry = @ptrCast(@alignCast(data.ptr));

        if (entry.mtime == mtime and entry.size == size) return true;

        return false;
    }

    /// Update cache for a file
    pub fn update(self: *Self, path: []const u8, hash: ?[32]u8, mtime: u64, size: usize) !void {
        const allocator = self.allocator;
        const cache_file = try self.computeCacheFilePath(path, hash);
        defer allocator.free(cache_file);

        self.mutex.lock();
        defer self.mutex.unlock();

        var file = try std.fs.cwd().createFile(cache_file, .{ .truncate = true });
        defer file.close();

        var entry = CacheEntry{
            .mtime = mtime,
            .size = size,
            .hash = if (hash) |h| h else [_]u8{0} ** 32,
            .path_len = @intCast(path.len),
        };

        const entry_bytes = std.mem.asBytes(&entry);
        try file.writeAll(entry_bytes);
        try file.writeAll(path);
    }

    /// Cleanup stale entries
    pub fn cleanup(self: *Self) !void {
        const cwd = std.fs.cwd();
        var dir = try cwd.openDir(self.cache_dir, .{ .iterate = true });
        defer dir.close();

        var it = dir.iterate();

        while (try it.next()) |entry| {
            // Only delete files
            if (entry.kind != .file) continue;

            // Build full path
            const full_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.cache_dir, entry.name });
            defer self.allocator.free(full_path);

            // Attempt to delete the file
            cwd.deleteFile(full_path) catch {};
        }
    }

    /// hash large file content
    pub fn hashFileContent(self: *Self, path: []const u8) ![32]u8 {
        const allocator = self.allocator;
        const cwd = std.fs.cwd();

        // Open file for reading
        const file = try cwd.openFile(path, .{ .mode = .read_only });
        defer file.close();

        // Read the entire file into memory
        const max_size = 100 * 1024 * 1024; // 100MB limit
        const data = try file.readToEndAlloc(allocator, max_size);
        defer allocator.free(data);

        // Compute hash
        var hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(data, &hash, .{});

        return hash;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.cache_dir);
    }
};
