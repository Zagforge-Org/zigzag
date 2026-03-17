const std = @import("std");

pub const ChunkMeta = struct {
    file_name: []const u8, // owned
    bytes: usize,
    files: []const []const u8, // owned slice of owned strings
    index: u32,
};

pub const ChunkWriter = struct {
    base_path: []const u8, // NOT owned (caller owns)
    root_path: []const u8, // NOT owned (caller owns)
    chunk_limit: usize,
    current_bytes: usize,
    chunk_index: u32,
    file: std.fs.File,
    finalized: bool,
    chunk_metas: std.ArrayList(ChunkMeta),
    current_chunk_files: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(base_path: []const u8, root_path: []const u8, chunk_limit: usize, allocator: std.mem.Allocator) !ChunkWriter {
        const path = try chunkFileName(base_path, 1, allocator);
        defer allocator.free(path);
        const file = try std.fs.cwd().createFile(path, .{});
        return ChunkWriter{
            .base_path = base_path,
            .root_path = root_path,
            .chunk_limit = chunk_limit,
            .current_bytes = 0,
            .chunk_index = 1,
            .file = file,
            .finalized = false,
            .chunk_metas = .empty,
            .current_chunk_files = .empty,
            .allocator = allocator,
        };
    }

    /// Write raw bytes to current chunk. Does NOT trigger rotation.
    pub fn writeRaw(self: *ChunkWriter, content: []const u8) !void {
        try self.file.writeAll(content);
        self.current_bytes += content.len;
    }

    /// Add a file path to the current chunk's file list (after writing its content via writeRaw).
    pub fn addCurrentFile(self: *ChunkWriter, path: []const u8) !void {
        const owned = try self.allocator.dupe(u8, path);
        try self.current_chunk_files.append(self.allocator, owned);
    }

    /// Seal current chunk and open a new one. Caller must write continuation header afterward.
    pub fn rotateChunk(self: *ChunkWriter) !void {
        // Seal current chunk
        const file_name = try chunkFileName(self.base_path, self.chunk_index, self.allocator);
        const owned_files = try self.current_chunk_files.toOwnedSlice(self.allocator);
        try self.chunk_metas.append(self.allocator, ChunkMeta{
            .file_name = file_name,
            .bytes = self.current_bytes,
            .files = owned_files,
            .index = self.chunk_index,
        });
        // Open next chunk
        self.file.close();
        self.chunk_index += 1;
        self.current_bytes = 0;
        self.current_chunk_files = .empty;
        const next_path = try chunkFileName(self.base_path, self.chunk_index, self.allocator);
        defer self.allocator.free(next_path);
        self.file = try std.fs.cwd().createFile(next_path, .{});
    }

    /// Write file content. Triggers rotation if content would overflow chunk (and chunk non-empty).
    /// After rotation, caller is responsible for writing the continuation header via writeRaw.
    /// For use in single-pass mode where caller handles continuation headers.
    pub fn writeFile(self: *ChunkWriter, path: []const u8, content: []const u8) !void {
        if (content.len + self.current_bytes > self.chunk_limit and self.current_bytes > 0) {
            try self.rotateChunk();
        }
        try self.writeRaw(content);
        try self.addCurrentFile(path);
    }

    /// Finalize: seal last chunk, close file, write manifest if multi-chunk.
    pub fn finalize(self: *ChunkWriter) !void {
        std.debug.assert(!self.finalized);
        // Seal last chunk
        const file_name = try chunkFileName(self.base_path, self.chunk_index, self.allocator);
        const owned_files = try self.current_chunk_files.toOwnedSlice(self.allocator);
        try self.chunk_metas.append(self.allocator, ChunkMeta{
            .file_name = file_name,
            .bytes = self.current_bytes,
            .files = owned_files,
            .index = self.chunk_index,
        });
        self.file.close();
        self.finalized = true;
        // Write manifest only for multi-chunk
        if (self.chunk_index > 1) {
            try self.writeManifest();
        }
    }

    pub fn deinit(self: *ChunkWriter) void {
        if (!self.finalized) self.file.close();
        for (self.chunk_metas.items) |meta| {
            self.allocator.free(meta.file_name);
            for (meta.files) |f| self.allocator.free(f);
            self.allocator.free(meta.files);
        }
        self.chunk_metas.deinit(self.allocator);
        for (self.current_chunk_files.items) |f| self.allocator.free(f);
        self.current_chunk_files.deinit(self.allocator);
    }

    fn writeManifest(self: *ChunkWriter) !void {
        const manifest_path = try std.mem.concat(self.allocator, u8, &.{ self.base_path, ".manifest.json" });
        defer self.allocator.free(manifest_path);
        const mf = try std.fs.cwd().createFile(manifest_path, .{});
        defer mf.close();

        // Build JSON using std.io.Writer.Allocating
        var aw: std.io.Writer.Allocating = .init(self.allocator);
        defer aw.deinit();

        const ts_raw = std.time.timestamp();
        const ts: u64 = if (ts_raw > 0) @intCast(ts_raw) else 0;
        const es = std.time.epoch.EpochSeconds{ .secs = ts };
        const ed = es.getEpochDay();
        const yd = ed.calculateYearDay();
        const md = yd.calculateMonthDay();
        const ds = es.getDaySeconds();
        var ts_buf: [32]u8 = undefined;
        const ts_str = std.fmt.bufPrint(&ts_buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
            yd.year,
            md.month.numeric(),
            md.day_index + 1,
            ds.getHoursIntoDay(),
            ds.getMinutesIntoHour(),
            ds.getSecondsIntoMinute(),
        }) catch "1970-01-01T00:00:00Z";

        var ws: std.json.Stringify = .{ .writer = &aw.writer, .options = .{ .whitespace = .indent_2 } };
        try ws.beginObject();
        try ws.objectField("version");
        try ws.write("1");
        try ws.objectField("root_path");
        try ws.write(self.root_path);
        try ws.objectField("generated_at");
        try ws.write(ts_str);
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

        try mf.writeAll(aw.written());
    }
};

/// Returns the chunk file name. Caller must free.
/// Chunk 1: base_path ++ ".md"
/// Chunk N: base_path ++ "-N.md"
pub fn chunkFileName(base_path: []const u8, index: u32, allocator: std.mem.Allocator) ![]u8 {
    if (index == 1) {
        return std.mem.concat(allocator, u8, &.{ base_path, ".md" });
    }
    var idx_buf: [16]u8 = undefined;
    const idx_str = std.fmt.bufPrint(&idx_buf, "{d}", .{index}) catch unreachable;
    return std.mem.concat(allocator, u8, &.{ base_path, "-", idx_str, ".md" });
}
