//! Content sidecars which the browser fetches source bodies from these separately from the dashboard payload.
//! Two shapes: a single JSON map, or one flat hash-named file per source.
//! Plus the watch-mode stamp.
const std = @import("std");
const JobEntry = @import("../../../../../jobs/entries.zig").JobEntry;

/// Per-path entry for the combined content writers.
pub const CombinedContentPath = struct {
    root_path: []const u8,
    file_entries: *const std.StringHashMap(JobEntry),
};

/// Write the watch-mode stamp sidecar: a tiny file holding only the generated_at
/// timestamp.
pub fn writeStampFile(io: std.Io, html_path: []const u8, generated_at: []const u8, allocator: std.mem.Allocator) !void {
    const stamp_path = try std.fmt.allocPrint(allocator, "{s}.stamp", .{html_path});
    defer allocator.free(stamp_path);
    var stamp_file = try std.Io.Dir.cwd().createFile(io, stamp_path, .{ .truncate = true });
    defer stamp_file.close(io);
    try stamp_file.writeStreamingAll(io, generated_at);
}

/// Encode a single value as a JSON string and stream it to `file`.
fn writeJsonValue(io: std.Io, file: std.Io.File, allocator: std.mem.Allocator, value: anytype) !void {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    var ws: std.json.Stringify = .{ .writer = &aw.writer, .options = .{} };
    try ws.write(value);
    try file.writeStreamingAll(io, aw.written());
}

/// Stream source content to a sidecar JSON file: {"path":"content",...}.
pub fn writeContentJson(
    io: std.Io,
    file_entries: *const std.StringHashMap(JobEntry),
    content_path: []const u8,
    allocator: std.mem.Allocator,
) !void {
    var file = try std.Io.Dir.cwd().createFile(io, content_path, .{ .truncate = true });
    defer file.close(io);

    try file.writeStreamingAll(io, "{");
    var first = true;
    var it = file_entries.iterator();
    while (it.next()) |kv| {
        if (!first) try file.writeStreamingAll(io, ",");
        first = false;
        try writeJsonValue(io, file, allocator, kv.key_ptr.*);
        try file.writeStreamingAll(io, ":");
        try writeJsonValue(io, file, allocator, kv.value_ptr.content);
    }
    try file.writeStreamingAll(io, "}");
}

/// Write a merged content sidecar for the combined report.
pub fn writeCombinedContentJson(
    io: std.Io,
    paths: []const CombinedContentPath,
    content_path: []const u8,
    allocator: std.mem.Allocator,
) !void {
    var file = try std.Io.Dir.cwd().createFile(io, content_path, .{ .truncate = true });
    defer file.close(io);

    try file.writeStreamingAll(io, "{");
    var first = true;
    for (paths) |p| {
        var it = p.file_entries.iterator();
        while (it.next()) |kv| {
            if (!first) try file.writeStreamingAll(io, ",");
            first = false;

            const combined_key = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ p.root_path, kv.key_ptr.* });
            defer allocator.free(combined_key);

            try writeJsonValue(io, file, allocator, combined_key);
            try file.writeStreamingAll(io, ":");
            try writeJsonValue(io, file, allocator, kv.value_ptr.content);
        }
    }
    try file.writeStreamingAll(io, "}");
}

/// FNV-1a 32-bit.
/// Hash algorithm is the identical algorithm to fnv1a32() in content.ts.
fn fnv1a32Hash(s: []const u8) u32 {
    var h: u32 = 2166136261;
    for (s) |b| {
        h ^= b;
        h = h *% 16777619;
    }
    return h;
}

/// Write `content` to `content_dir`, named by the 8-char lowercase hex FNV-1a hash of `key`.
fn writeContentFile(io: std.Io, content_dir: []const u8, key: []const u8, content: []const u8, allocator: std.mem.Allocator) !void {
    var hex_buf: [8]u8 = undefined;
    const hex = try std.fmt.bufPrint(&hex_buf, "{x:0>8}", .{fnv1a32Hash(key)});
    const fname = try std.fs.path.join(allocator, &.{ content_dir, hex });
    defer allocator.free(fname);
    var f = try std.Io.Dir.cwd().createFile(io, fname, .{ .truncate = true });
    defer f.close(io);
    try f.writeStreamingAll(io, content);
}

/// Write source content as individual hash-named files in a flat content directory.
pub fn writeContentFiles(
    io: std.Io,
    file_entries: *const std.StringHashMap(JobEntry),
    content_dir: []const u8,
    allocator: std.mem.Allocator,
) !void {
    try std.Io.Dir.cwd().createDirPath(io, content_dir);
    var it = file_entries.iterator();
    while (it.next()) |kv| {
        try writeContentFile(io, content_dir, kv.key_ptr.*, kv.value_ptr.content, allocator);
    }
}

/// Write content sidecars only for `changed_paths` (watch-mode incremental update).
/// Paths absent from file_entries (deleted or owned by another state) are skipped.
pub fn writeChangedContentFiles(
    io: std.Io,
    file_entries: *const std.StringHashMap(JobEntry),
    changed_paths: []const []const u8,
    content_dir: []const u8,
    allocator: std.mem.Allocator,
) !void {
    try std.Io.Dir.cwd().createDirPath(io, content_dir);
    for (changed_paths) |path| {
        const entry = file_entries.get(path) orelse continue;
        try writeContentFile(io, content_dir, path, entry.content, allocator);
    }
}

/// Write combined multi-path content as individual files.
pub fn writeCombinedContentFiles(
    io: std.Io,
    paths: []const CombinedContentPath,
    content_dir: []const u8,
    allocator: std.mem.Allocator,
) !void {
    try std.Io.Dir.cwd().createDirPath(io, content_dir);
    for (paths) |p| {
        var it = p.file_entries.iterator();
        while (it.next()) |kv| {
            const combined_key = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ p.root_path, kv.key_ptr.* });
            defer allocator.free(combined_key);
            try writeContentFile(io, content_dir, combined_key, kv.value_ptr.content, allocator);
        }
    }
}

/// Write combined content sidecars only for `changed_file_paths`. For each, the owning
/// CombinedContentPath is found by root_path prefix.
pub fn writeCombinedChangedContentFiles(
    io: std.Io,
    paths: []const CombinedContentPath,
    changed_file_paths: []const []const u8,
    content_dir: []const u8,
    allocator: std.mem.Allocator,
) !void {
    try std.Io.Dir.cwd().createDirPath(io, content_dir);
    for (changed_file_paths) |changed_path| {
        var owning_path: ?CombinedContentPath = null;
        for (paths) |p| {
            if (std.mem.startsWith(u8, changed_path, p.root_path)) {
                owning_path = p;
                break;
            }
        }
        const p = owning_path orelse continue;
        const entry = p.file_entries.get(changed_path) orelse continue;

        const combined_key = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ p.root_path, changed_path });
        defer allocator.free(combined_key);
        try writeContentFile(io, content_dir, combined_key, entry.content, allocator);
    }
}
