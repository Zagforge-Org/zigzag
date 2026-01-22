const std = @import("std");

/// CacheEntry with position tracking in the report
const CacheEntry = struct {
    mtime: u64,
    size: usize,
    content: []u8,
    start_pos: usize, // Where this file's content starts in report.md
    end_pos: usize, // Where this file's content ends in report.md
};

pub const FileCache = struct {
    allocator: std.mem.Allocator,
    cache_dir: []const u8,
    small_file_threshold: usize,
    memory_cache: std.StringHashMap(CacheEntry),
    mutex: std.Thread.Mutex,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, cache_dir: []const u8, small_file_threshold: usize) !Self {
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

        const data = try file.readToEndAlloc(self.allocator, 100 * 1024 * 1024);
        defer self.allocator.free(data);

        var lines = std.mem.splitSequence(u8, data, "\n");
        while (lines.next()) |line| {
            if (line.len == 0) continue;

            // Format: path|mtime|size|start_pos|end_pos|content_file
            var parts = std.mem.splitSequence(u8, line, "|");
            const path = parts.next() orelse continue;
            const mtime_str = parts.next() orelse continue;
            const size_str = parts.next() orelse continue;
            const start_str = parts.next() orelse continue;
            const end_str = parts.next() orelse continue;
            const content_file = parts.next() orelse continue;

            const mtime = std.fmt.parseInt(u64, mtime_str, 10) catch continue;
            const size = std.fmt.parseInt(usize, size_str, 10) catch continue;
            const start_pos = std.fmt.parseInt(usize, start_str, 10) catch continue;
            const end_pos = std.fmt.parseInt(usize, end_str, 10) catch continue;

            const content_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.cache_dir, content_file });
            defer self.allocator.free(content_path);

            const content = std.fs.cwd().readFileAlloc(self.allocator, content_path, 100 * 1024 * 1024) catch continue;

            const path_copy = try self.allocator.dupe(u8, path);
            try self.memory_cache.put(path_copy, .{
                .mtime = mtime,
                .size = size,
                .content = content,
                .start_pos = start_pos,
                .end_pos = end_pos,
            });
        }
    }

    fn saveToDisk(self: *Self) !void {
        const cache_index_path = try std.fmt.allocPrint(self.allocator, "{s}/index", .{self.cache_dir});
        defer self.allocator.free(cache_index_path);

        var file = try std.fs.cwd().createFile(cache_index_path, .{ .truncate = true });
        defer file.close();

        var it = self.memory_cache.iterator();
        var counter: usize = 0;
        while (it.next()) |entry| {
            const content_filename = try std.fmt.allocPrint(self.allocator, "content_{d}", .{counter});
            defer self.allocator.free(content_filename);

            const content_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.cache_dir, content_filename });
            defer self.allocator.free(content_path);

            var content_file = try std.fs.cwd().createFile(content_path, .{ .truncate = true });
            defer content_file.close();
            try content_file.writeAll(entry.value_ptr.content);

            const line = try std.fmt.allocPrint(self.allocator, "{s}|{d}|{d}|{d}|{d}|{s}\n", .{
                entry.key_ptr.*,
                entry.value_ptr.mtime,
                entry.value_ptr.size,
                entry.value_ptr.start_pos,
                entry.value_ptr.end_pos,
                content_filename,
            });
            defer self.allocator.free(line);
            try file.writeAll(line);

            counter += 1;
        }
    }

    pub fn isCached(self: *Self, path: []const u8, mtime: u64, size: usize, _: ?[32]u8) !bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        const entry = self.memory_cache.get(path) orelse return false;
        return entry.mtime == mtime and entry.size == size;
    }

    pub fn getCachedEntry(self: *Self, path: []const u8) !?CacheEntry {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.memory_cache.get(path);
    }

    pub fn update(self: *Self, path: []const u8, _: ?[32]u8, mtime: u64, size: usize, content: []const u8, start_pos: usize, end_pos: usize) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.memory_cache.getPtr(path)) |entry_ptr| {
            self.allocator.free(entry_ptr.content);
            const content_copy = try self.allocator.dupe(u8, content);
            entry_ptr.mtime = mtime;
            entry_ptr.size = size;
            entry_ptr.content = content_copy;
            entry_ptr.start_pos = start_pos;
            entry_ptr.end_pos = end_pos;
        } else {
            const path_copy = try self.allocator.dupe(u8, path);
            const content_copy = try self.allocator.dupe(u8, content);
            try self.memory_cache.put(path_copy, .{
                .mtime = mtime,
                .size = size,
                .content = content_copy,
                .start_pos = start_pos,
                .end_pos = end_pos,
            });
        }
    }

    pub fn cleanup(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var it = self.memory_cache.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.content);
        }
        self.memory_cache.clearAndFree();

        var dir = try std.fs.cwd().openDir(self.cache_dir, .{ .iterate = true });
        defer dir.close();

        var dir_it = dir.iterate();
        while (try dir_it.next()) |entry| {
            dir.deleteFile(entry.name) catch {};
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
            self.allocator.free(entry.value_ptr.content);
        }
        self.memory_cache.deinit();
        self.allocator.free(self.cache_dir);
    }
};
