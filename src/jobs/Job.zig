//! A single file-processing unit run on the worker pool.

const std = @import("std");

const FileContext = @import("../cli/context.zig").FileContext;
const Cache = @import("../cache/Cache.zig");
const ProcessStats = @import("../cli/commands/stats.zig").ProcessStats;
const JobEntry = @import("entries.zig").JobEntry;
const BinaryEntry = @import("entries.zig").BinaryEntry;
const fs = @import("../fs/file.zig");
const inspect = @import("inspect.zig");
const JobContext = @import("../workers/Pool.zig").JobContext;

const Stat = std.Io.File.Stat;

const Self = @This();

path: []const u8,
file_ctx: ?*FileContext,
cache: ?*Cache,
stats: *ProcessStats,
file_entries: *std.StringHashMap(JobEntry),
binary_entries: *std.StringHashMap(BinaryEntry),
entries_mutex: *std.Io.Mutex,
allocator: std.mem.Allocator,

pub fn deinit(self: *Self) void {
    self.allocator.free(self.path);
}

/// Pool entry point.
pub fn process(self: Self, ctx: JobContext) anyerror!void {
    var job = self;
    defer job.deinit();

    const io = ctx.io;

    if (self.file_ctx) |fc| {
        if (inspect.shouldIgnore(self.path, fc.ignore_list)) {
            _ = self.stats.ignored_files.fetchAdd(1, .monotonic);
            return;
        }
    }

    const stat = std.Io.Dir.cwd().statFile(io, self.path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.log.debug("File not found (may have been moved/deleted): {s}", .{self.path});
            _ = self.stats.ignored_files.fetchAdd(1, .monotonic);
        } else {
            std.log.debug("Failed to stat file {s}: {}", .{ self.path, err });
        }
        return;
    };

    if (stat.size == 0) {
        std.log.debug("Skipping empty file: {s}", .{self.path});
        _ = self.stats.ignored_files.fetchAdd(1, .monotonic);
        return;
    }

    const read = self.readContent(io, stat) orelse return;

    if (inspect.isBinaryFile(self.path, read.content)) {
        try self.storeBinary(io, stat, read.content, read.counted_as_cached);
    } else {
        try self.storeText(io, stat, read.content);
    }
}

const Read = struct {
    content: []u8,
    counted_as_cached: bool,
};

/// Read the file from cache when the entry is still valid, otherwise from disk.
fn readContent(self: Self, io: std.Io, stat: Stat) ?Read {
    const allocator = self.allocator;
    const path = self.path;
    const stats = self.stats;
    const size = stat.size;
    const mtime_seconds: u64 = @intCast(stat.mtime.toSeconds());

    const cache = self.cache orelse {
        std.log.debug("Processing (no cache): {s}", .{path});
        _ = stats.processed_files.fetchAdd(1, .monotonic);
        const content = fs.readFileAlloc(io, allocator, path) catch |err| {
            std.log.debug("Failed to read {s}: {}", .{ path, err });
            _ = stats.processed_files.fetchSub(1, .monotonic);
            _ = stats.ignored_files.fetchAdd(1, .monotonic);
            return null;
        };
        return .{ .content = content, .counted_as_cached = false };
    };

    var hash: ?[32]u8 = null;
    if (size > cache.small_file_threshold) {
        hash = cache.hashFileContent(path) catch |err| {
            std.log.debug("Failed to hash file {s}: {}", .{ path, err });
            return null;
        };
    }

    const is_cached = cache.isCached(path, mtime_seconds, size, hash) catch false;
    if (is_cached) {
        std.log.debug("Cached (reading from .cache): {s}", .{path});
        _ = stats.cached_files.fetchAdd(1, .monotonic);

        // Flips to false if the cache read fails and we fall back to reading fresh.
        var counted_as_cached = true;
        const content = cache.getCachedContent(path) catch blk: {
            std.log.warn("Cache hit but failed for {s}, reading original", .{path});
            counted_as_cached = false;
            _ = stats.cached_files.fetchSub(1, .monotonic);
            _ = stats.processed_files.fetchAdd(1, .monotonic);

            const original = fs.readFileAlloc(io, allocator, path) catch |read_err| {
                std.log.err("Failed to read {s}: {}", .{ path, read_err });
                return null;
            };
            cache.update(path, hash, mtime_seconds, size, original) catch {};
            break :blk original;
        };
        return .{ .content = content, .counted_as_cached = counted_as_cached };
    }

    std.log.debug("Processing (reading original): {s}", .{path});
    _ = stats.processed_files.fetchAdd(1, .monotonic);

    const content = fs.readFileAlloc(io, allocator, path) catch |err| {
        std.log.debug("Failed to read {s}: {}", .{ path, err });
        _ = stats.processed_files.fetchSub(1, .monotonic);
        _ = stats.ignored_files.fetchAdd(1, .monotonic);
        return null;
    };
    cache.update(path, hash, mtime_seconds, size, content) catch |err| {
        std.log.err("Cache update failed for {s}: {}", .{ path, err });
    };
    return .{ .content = content, .counted_as_cached = false };
}

/// Record a binary file: free its content, move the tally from cached/processed
/// to binary, and store a BinaryEntry.
fn storeBinary(self: Self, io: std.Io, stat: Stat, content: []u8, counted_as_cached: bool) !void {
    std.log.debug("Skipping binary file: {s}", .{self.path});
    self.allocator.free(content);
    _ = self.stats.binary_files.fetchAdd(1, .monotonic);
    // Back out of whichever counter readContent bumped.
    if (counted_as_cached) {
        _ = self.stats.cached_files.fetchSub(1, .monotonic);
    } else {
        _ = self.stats.processed_files.fetchSub(1, .monotonic);
    }

    self.entries_mutex.lockUncancelable(io);
    defer self.entries_mutex.unlock(io);

    const path_copy = try self.allocator.dupe(u8, self.path);
    const ext_copy = try self.allocator.dupe(u8, inspect.getExtension(self.path));
    try self.binary_entries.put(path_copy, .{
        .path = path_copy,
        .size = stat.size,
        .mtime = stat.mtime.nanoseconds,
        .extension = ext_copy,
    });
}

/// Record a text file: count its lines and store a JobEntry that owns `content`.
fn storeText(self: Self, io: std.Io, stat: Stat, content: []u8) !void {
    const line_count = inspect.countLines(content);

    self.entries_mutex.lockUncancelable(io);
    defer self.entries_mutex.unlock(io);

    const path_copy = try self.allocator.dupe(u8, self.path);
    const ext_copy = try self.allocator.dupe(u8, inspect.getExtension(self.path));
    try self.file_entries.put(path_copy, .{
        .path = path_copy,
        .content = content,
        .size = stat.size,
        .mtime = stat.mtime.nanoseconds,
        .extension = ext_copy,
        .line_count = line_count,
    });
}
