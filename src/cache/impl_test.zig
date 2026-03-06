const std = @import("std");
const CacheImpl = @import("./impl.zig").CacheImpl;

/// Stat a file and return its mtime in SECONDS (matching what processFileJob stores).
fn mtimeSeconds(dir: std.fs.Dir, name: []const u8) !u64 {
    const s = try dir.statFile(name);
    return @intCast(@divFloor(s.mtime, std.time.ns_per_s));
}

fn fileSize(dir: std.fs.Dir, name: []const u8) !usize {
    const s = try dir.statFile(name);
    return s.size;
}

test "validateCache does not invalidate an unmodified file" {
    // This tests the mtime-units bug: validateCache must use seconds, not ns.
    const alloc = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    // Create real source file
    {
        const f = try tmp.dir.createFile("file.zig", .{});
        defer f.close();
        try f.writeAll("const x = 1;\n");
    }

    const file_abs = try std.fs.path.join(alloc, &.{ tmp_path, "file.zig" });
    defer alloc.free(file_abs);

    const cache_dir = try std.fs.path.join(alloc, &.{ tmp_path, ".cache" });
    defer alloc.free(cache_dir);

    // First session: populate cache
    {
        var cache = try CacheImpl.init(alloc, cache_dir, 1 << 20);
        const mtime_s = try mtimeSeconds(tmp.dir, "file.zig");
        const size = try fileSize(tmp.dir, "file.zig");
        try cache.update(file_abs, null, mtime_s, size, "const x = 1;\n");
        try cache.saveToDisk();
        cache.deinit();
    }

    // Second session: reload — validateCache must NOT evict the entry
    {
        var cache = try CacheImpl.init(alloc, cache_dir, 1 << 20);
        defer cache.deinit();

        const mtime_s = try mtimeSeconds(tmp.dir, "file.zig");
        const size = try fileSize(tmp.dir, "file.zig");
        const hit = try cache.isCached(file_abs, mtime_s, size, null);
        try std.testing.expect(hit);
    }
}

test "cache survives a full init/saveToDisk/deinit/init round-trip" {
    const alloc = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    {
        const f = try tmp.dir.createFile("hello.zig", .{});
        defer f.close();
        try f.writeAll("// hello\n");
    }

    const file_abs = try std.fs.path.join(alloc, &.{ tmp_path, "hello.zig" });
    defer alloc.free(file_abs);

    const cache_dir = try std.fs.path.join(alloc, &.{ tmp_path, ".cache" });
    defer alloc.free(cache_dir);

    const mtime_s = try mtimeSeconds(tmp.dir, "hello.zig");
    const size = try fileSize(tmp.dir, "hello.zig");

    // Session 1 — write
    {
        var cache = try CacheImpl.init(alloc, cache_dir, 1 << 20);
        try cache.update(file_abs, null, mtime_s, size, "// hello\n");
        try cache.saveToDisk();
        cache.deinit();
    }

    // Session 2 — verify hit and content
    {
        var cache = try CacheImpl.init(alloc, cache_dir, 1 << 20);
        defer cache.deinit();

        try std.testing.expect(try cache.isCached(file_abs, mtime_s, size, null));

        const content = try cache.getCachedContent(file_abs);
        defer alloc.free(content);
        try std.testing.expectEqualStrings("// hello\n", content);
    }
}

test "validateCache evicts entries for deleted files" {
    const alloc = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    {
        const f = try tmp.dir.createFile("gone.zig", .{});
        defer f.close();
        try f.writeAll("// temp\n");
    }

    const file_abs = try std.fs.path.join(alloc, &.{ tmp_path, "gone.zig" });
    defer alloc.free(file_abs);

    const cache_dir = try std.fs.path.join(alloc, &.{ tmp_path, ".cache" });
    defer alloc.free(cache_dir);

    // Session 1 — cache the file
    {
        var cache = try CacheImpl.init(alloc, cache_dir, 1 << 20);
        const mtime_s = try mtimeSeconds(tmp.dir, "gone.zig");
        const size = try fileSize(tmp.dir, "gone.zig");
        try cache.update(file_abs, null, mtime_s, size, "// temp\n");
        try cache.saveToDisk();
        cache.deinit();
    }

    // Delete the file
    try tmp.dir.deleteFile("gone.zig");

    // Session 2 — validateCache should evict the stale entry
    {
        var cache = try CacheImpl.init(alloc, cache_dir, 1 << 20);
        defer cache.deinit();

        const hit = cache.isCached(file_abs, 0, 0, null) catch false;
        try std.testing.expect(!hit);
    }
}

test "validateCache evicts entries whose mtime changed" {
    const alloc = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    {
        const f = try tmp.dir.createFile("changing.zig", .{});
        defer f.close();
        try f.writeAll("v1\n");
    }

    const file_abs = try std.fs.path.join(alloc, &.{ tmp_path, "changing.zig" });
    defer alloc.free(file_abs);

    const cache_dir = try std.fs.path.join(alloc, &.{ tmp_path, ".cache" });
    defer alloc.free(cache_dir);

    // Session 1 — cache with a deliberately wrong (old) mtime
    {
        var cache = try CacheImpl.init(alloc, cache_dir, 1 << 20);
        const size = try fileSize(tmp.dir, "changing.zig");
        // Store mtime = 1 (epoch+1s) — guaranteed to differ from the real file
        try cache.update(file_abs, null, 1, size, "v1\n");
        try cache.saveToDisk();
        cache.deinit();
    }

    // Session 2 — reload; validateCache sees real mtime != 1 → evicts
    {
        var cache = try CacheImpl.init(alloc, cache_dir, 1 << 20);
        defer cache.deinit();

        const mtime_s = try mtimeSeconds(tmp.dir, "changing.zig");
        const size = try fileSize(tmp.dir, "changing.zig");
        const hit = try cache.isCached(file_abs, mtime_s, size, null);
        try std.testing.expect(!hit);
    }
}

test "isCached returns false for unknown path" {
    const alloc = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    const cache_dir = try std.fs.path.join(alloc, &.{ tmp_path, ".cache" });
    defer alloc.free(cache_dir);

    var cache = try CacheImpl.init(alloc, cache_dir, 1 << 20);
    defer cache.deinit();

    const hit = try cache.isCached("/nonexistent/path.zig", 12345, 100, null);
    try std.testing.expect(!hit);
}
