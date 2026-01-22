const std = @import("std");

const SEED: u64 = 0x123456789ABCDEF0;

/// CacheEntry represents an entry in the file cache.
const CacheEntry = packed struct {
    path_len: u32,
    mtime: u64,
    size: usize,
    hash: [32]u8,
};

pub const FileCache = struct {
    allocator: std.mem.Allocator,
    cache_dir: ?[]const u8,
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

    /// Compute a simple hash or fast path for filename
    fn computeCacheFilePath(self: *Self, path: []const u8, hash: ?[32]u8) []u8 {
        const allocator = self.allocator;
        if (hash) |h| {
            // Allocate space for the hex representation of the hash:
            // - 64 bytes for a SHA-256 hash (32 bytes * 2 hex chars per byte)
            // - +4 bytes as extra buffer for safety, null-terminator, or small suffixes
            var hex_path = try allocator.alloc(u8, 64 + 4);
            const len = try std.fmt.format(hex_path, "{s}/{*x}", .{ self.cache_dir, h[0..] });
            return hex_path[0..len];
        } else {
            // Small file fast path
            const sanitized = std.mem.replace(path, "/", "_");
            // Allocate a buffer large enough for the full cache file path:
            // - self.cache_dir.len → space for the cache directory string
            // - 1 → space for the '/' character between directory and filename
            // - sanitized.len → space for the sanitized filename
            const full_path = try allocator.alloc(u8, self.cache_dir.len + 1 + sanitized.len);
            std.mem.copy(u8, full_path[0..self.cache_dir.len], self.cache_dir);
            return full_path;
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
                _ => return err,
            }
        };

        defer file.close();

        const data = try file.readToEndAlloc(allocator, 8192);
        defer allocator.free(data);

        if (data.len < @sizeOf(CacheEntry)) return false;

        const entry: *const CacheEntry = @ptrCast(data.ptr);

        if (entry.mtime == mtime and entry.size == size) return true;

        return false;
    }

    /// Update cache for a file
    pub fn update(self: *FileCache, path: []const u8, hash: ?[32]u8, mtime: u64, size: usize) !void {
        const allocator = self.allocator;
        const cache_file = try self.computeCacheFilePath(path, hash);
        defer allocator.free(cache_file);

        var file = try std.fs.cwd().createFile(cache_file, .{ .truncate = true });
        defer file.close();

        var entry: CacheEntry = CacheEntry{
            .mtime = mtime,
            .size = size,
            .hash = if (hash) |h| h else [_]u8{0} ** 32,
            .path_len = @intCast(path.len),
        };

        const entryPtr: [*]const u8 = @ptrCast(&entry);

        try file.writeAll(entryPtr);
        try file.writeAll(path);
    }

    /// Cleanup stale entries
    pub fn cleanup(self: *Self) !void {
        const cwd = std.fs.cwd();
        const dir = try cwd.openDir(self.cache_dir, .{ .iterate = true });
        defer dir.close();

        var it = dir.iterate();

        while (true) {
            const maybe_entry = it.next();
            if (maybe_entry == null) break; // iteration done
            const entry: std.fs.Dir.Entry = maybe_entry.?;

            // Only delete files
            if (entry.kind != .file) continue;

            // Build full path
            const full_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.cache_dir, entry.name });
            defer self.allocator.free(full_path);

            // Attempt to delete the file
            _ = cwd.deleteFile(full_path) catch {};
        }
    }

    /// hash large file content
    pub fn hashFileContent(self: *Self, path: []const u8) ![32]u8 {
        const allocator = self.allocator;
        const cwd = std.fs.cwd();

        //  Open file for reading
        const file = try cwd.openFile(path, .{ .mode = .read_only });
        defer file.close();

        // Read the entire file into memory
        const data = try file.readToEndAlloc(allocator, 8192);
        defer allocator.free(data);

        // Comopute sha-256 hash
        var hasher = std.hash.XxHash3.init(SEED);
        hasher.update(data);

        return hasher.final();
    }

    pub fn deinit(self: *Self) void {
        if (self.cache_dir) |dir| {
            self.allocator.free(dir);
            self.cache_dir = null;
        }
    }
};
