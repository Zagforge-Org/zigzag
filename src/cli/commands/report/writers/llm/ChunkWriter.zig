//! Chunked LLM report writer. Streams file bodies into size-bounded `.md` chunks,
//! rotating to a fresh chunk whenever a write would overflow the current one, and
//! emits a sibling `.manifest.json` when more than one chunk was produced.

const std = @import("std");

pub const ChunkMeta = struct {
    file_name: []const u8,
    bytes: usize,
    files: []const []const u8,
    index: u32,
};

const Self = @This();

io: std.Io,
base_path: []const u8,
root_path: []const u8,
chunk_limit: usize,
current_bytes: usize,
chunk_index: u32,
file: std.Io.File,
finalized: bool,
chunk_metas: std.ArrayList(ChunkMeta),
current_chunk_files: std.ArrayList([]const u8),
allocator: std.mem.Allocator,

pub fn init(io: std.Io, base_path: []const u8, root_path: []const u8, chunk_limit: usize, allocator: std.mem.Allocator) !Self {
    const path = try chunkFileName(base_path, 1, allocator);
    defer allocator.free(path);
    return .{
        .io = io,
        .base_path = base_path,
        .root_path = root_path,
        .chunk_limit = chunk_limit,
        .current_bytes = 0,
        .chunk_index = 1,
        .file = try std.Io.Dir.cwd().createFile(io, path, .{}),
        .finalized = false,
        .chunk_metas = .empty,
        .current_chunk_files = .empty,
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    if (!self.finalized) self.file.close(self.io);
    for (self.chunk_metas.items) |meta| {
        self.allocator.free(meta.file_name);
        for (meta.files) |f| self.allocator.free(f);
        self.allocator.free(meta.files);
    }
    self.chunk_metas.deinit(self.allocator);
    for (self.current_chunk_files.items) |f| self.allocator.free(f);
    self.current_chunk_files.deinit(self.allocator);
}

/// Write raw bytes to the current chunk.
pub fn writeRaw(self: *Self, content: []const u8) !void {
    try self.file.writeStreamingAll(self.io, content);
    self.current_bytes += content.len;
}

/// Record `path` as belonging to the current chunk.
pub fn addCurrentFile(self: *Self, path: []const u8) !void {
    const owned = try self.allocator.dupe(u8, path);
    try self.current_chunk_files.append(self.allocator, owned);
}

/// Write a file body, rotating to a new chunk first if it would overflow a
/// non-empty chunk. An oversized file still lands whole in its own fresh chunk.
pub fn writeFile(self: *Self, path: []const u8, content: []const u8) !void {
    if (self.current_bytes > 0 and self.current_bytes + content.len > self.chunk_limit) {
        try self.rotateChunk();
    }
    try self.writeRaw(content);
    try self.addCurrentFile(path);
}

/// Seal the current chunk and open the next one.
pub fn rotateChunk(self: *Self) !void {
    try self.sealCurrentChunk();

    self.file.close(self.io);
    self.chunk_index += 1;
    self.current_bytes = 0;

    const next_path = try chunkFileName(self.base_path, self.chunk_index, self.allocator);
    defer self.allocator.free(next_path);
    self.file = try std.Io.Dir.cwd().createFile(self.io, next_path, .{});
}

/// Seal the last chunk, close the file, and write the manifest when multi-chunk.
pub fn finalize(self: *Self) !void {
    std.debug.assert(!self.finalized);
    try self.sealCurrentChunk();
    self.file.close(self.io);
    self.finalized = true;
    if (self.chunk_index > 1) try self.writeManifest();
}

/// Append a ChunkMeta for the current chunk, transferring ownership of its file
/// list. Leaves `current_chunk_files` empty, ready for the next chunk.
fn sealCurrentChunk(self: *Self) !void {
    const file_name = try chunkFileName(self.base_path, self.chunk_index, self.allocator);
    errdefer self.allocator.free(file_name);
    const owned_files = try self.current_chunk_files.toOwnedSlice(self.allocator);
    errdefer {
        for (owned_files) |f| self.allocator.free(f);
        self.allocator.free(owned_files);
    }
    try self.chunk_metas.append(self.allocator, .{
        .file_name = file_name,
        .bytes = self.current_bytes,
        .files = owned_files,
        .index = self.chunk_index,
    });
}

fn writeManifest(self: *Self) !void {
    const manifest_path = try std.mem.concat(self.allocator, u8, &.{ self.base_path, ".manifest.json" });
    defer self.allocator.free(manifest_path);
    const mf = try std.Io.Dir.cwd().createFile(self.io, manifest_path, .{});
    defer mf.close(self.io);

    var aw: std.Io.Writer.Allocating = .init(self.allocator);
    defer aw.deinit();

    var ts_buf: [32]u8 = undefined;
    const generated_at = self.formatGeneratedAt(&ts_buf);

    var ws: std.json.Stringify = .{ .writer = &aw.writer, .options = .{ .whitespace = .indent_2 } };
    try ws.beginObject();
    try ws.objectField("version");
    try ws.write("1");
    try ws.objectField("root_path");
    try ws.write(self.root_path);
    try ws.objectField("generated_at");
    try ws.write(generated_at);
    try ws.objectField("chunk_size_bytes");
    try ws.write(self.chunk_limit);
    try ws.objectField("chunks");
    try ws.beginArray();
    for (self.chunk_metas.items) |meta| {
        try ws.beginObject();
        try ws.objectField("index");
        try ws.write(meta.index);
        try ws.objectField("file");
        try ws.write(meta.file_name);
        try ws.objectField("bytes");
        try ws.write(meta.bytes);
        try ws.objectField("files");
        try ws.beginArray();
        for (meta.files) |f| try ws.write(f);
        try ws.endArray();
        try ws.endObject();
    }
    try ws.endArray();
    try ws.endObject();

    try mf.writeStreamingAll(self.io, aw.written());
}

/// Format the current wall-clock time as an ISO-8601 UTC string into `buf`.
fn formatGeneratedAt(self: *Self, buf: []u8) []const u8 {
    const secs = std.Io.Timestamp.now(self.io, .real).toSeconds();
    const epoch: u64 = if (secs > 0) @intCast(secs) else 0;
    const es = std.time.epoch.EpochSeconds{ .secs = epoch };
    const yd = es.getEpochDay().calculateYearDay();
    const md = yd.calculateMonthDay();
    const ds = es.getDaySeconds();
    return std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        yd.year,
        md.month.numeric(),
        md.day_index + 1,
        ds.getHoursIntoDay(),
        ds.getMinutesIntoHour(),
        ds.getSecondsIntoMinute(),
    }) catch "1970-01-01T00:00:00Z";
}

pub fn chunkFileName(base_path: []const u8, index: u32, allocator: std.mem.Allocator) ![]u8 {
    if (index == 1) return std.mem.concat(allocator, u8, &.{ base_path, ".md" });
    var idx_buf: [16]u8 = undefined;
    const idx_str = std.fmt.bufPrint(&idx_buf, "{d}", .{index}) catch unreachable;
    return std.mem.concat(allocator, u8, &.{ base_path, "-", idx_str, ".md" });
}
