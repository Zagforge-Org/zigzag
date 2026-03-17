const std = @import("std");
const ChunkWriter = @import("chunk_writer.zig").ChunkWriter;
const chunkFileName = @import("chunk_writer.zig").chunkFileName;

test "chunkFileName: chunk 1 = base.md" {
    const name = try chunkFileName("report.llm", 1, std.testing.allocator);
    defer std.testing.allocator.free(name);
    try std.testing.expectEqualStrings("report.llm.md", name);
}

test "chunkFileName: chunk 2 = base-2.md" {
    const name = try chunkFileName("report.llm", 2, std.testing.allocator);
    defer std.testing.allocator.free(name);
    try std.testing.expectEqualStrings("report.llm-2.md", name);
}

test "ChunkWriter: single chunk no manifest" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const base_dir = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(base_dir);

    const base_path = try std.fs.path.join(std.testing.allocator, &.{ base_dir, "report.llm" });
    defer std.testing.allocator.free(base_path);

    var cw = try ChunkWriter.init(base_path, "src/", 10_000, std.testing.allocator);
    defer cw.deinit();

    try cw.writeFile("src/a.zig", "hello world\n");
    try cw.finalize();

    // chunk 1 exists
    const chunk1 = try std.fs.path.join(std.testing.allocator, &.{ base_dir, "report.llm.md" });
    defer std.testing.allocator.free(chunk1);
    const stat1 = try std.fs.cwd().statFile(chunk1);
    try std.testing.expect(stat1.size > 0);

    // no manifest
    const manifest_path = try std.fs.path.join(std.testing.allocator, &.{ base_dir, "report.llm.manifest.json" });
    defer std.testing.allocator.free(manifest_path);
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().statFile(manifest_path));

    try std.testing.expectEqual(@as(u32, 1), cw.chunk_index);
}

test "ChunkWriter: multi-chunk rotation and manifest" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const base_dir = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(base_dir);

    const base_path = try std.fs.path.join(std.testing.allocator, &.{ base_dir, "report.llm" });
    defer std.testing.allocator.free(base_path);

    // chunk_limit = 20 bytes, so 3 files of 10 bytes each → 3 chunks
    var cw = try ChunkWriter.init(base_path, "src/", 20, std.testing.allocator);
    defer cw.deinit();

    try cw.writeFile("src/a.zig", "0123456789"); // 10 bytes — chunk 1, total 10
    try cw.writeFile("src/b.zig", "0123456789"); // 10 bytes — 10+10=20 <= 20, still chunk 1
    try cw.writeFile("src/c.zig", "0123456789"); // 10 bytes — 20+10=30 > 20 → rotate to chunk 2
    try cw.finalize();

    // chunk 1 and chunk 2 exist
    const chunk1 = try std.fs.path.join(std.testing.allocator, &.{ base_dir, "report.llm.md" });
    defer std.testing.allocator.free(chunk1);
    const chunk2 = try std.fs.path.join(std.testing.allocator, &.{ base_dir, "report.llm-2.md" });
    defer std.testing.allocator.free(chunk2);
    _ = try std.fs.cwd().statFile(chunk1);
    _ = try std.fs.cwd().statFile(chunk2);

    // manifest exists
    const manifest_path = try std.fs.path.join(std.testing.allocator, &.{ base_dir, "report.llm.manifest.json" });
    defer std.testing.allocator.free(manifest_path);
    _ = try std.fs.cwd().statFile(manifest_path);

    try std.testing.expectEqual(@as(u32, 2), cw.chunk_index);
    try std.testing.expectEqual(@as(usize, 2), cw.chunk_metas.items.len);
}

test "ChunkWriter: oversized file gets own chunk" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const base_dir = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(base_dir);

    const base_path = try std.fs.path.join(std.testing.allocator, &.{ base_dir, "report.llm" });
    defer std.testing.allocator.free(base_path);

    // chunk_limit = 5 bytes, file is 20 bytes
    var cw = try ChunkWriter.init(base_path, "src/", 5, std.testing.allocator);
    defer cw.deinit();

    try cw.writeFile("src/big.zig", "01234567890123456789"); // 20 bytes > limit=5, but current_bytes=0 → no rotate
    try cw.finalize();

    // still chunk 1 (no rotation fired because current_bytes was 0)
    try std.testing.expectEqual(@as(u32, 1), cw.chunk_index);
}

test "ChunkWriter: exact limit does not rotate" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const base_dir = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(base_dir);

    const base_path = try std.fs.path.join(std.testing.allocator, &.{ base_dir, "report.llm" });
    defer std.testing.allocator.free(base_path);

    // chunk_limit = 10 bytes, file is exactly 10 bytes
    var cw = try ChunkWriter.init(base_path, "src/", 10, std.testing.allocator);
    defer cw.deinit();

    try cw.writeFile("src/a.zig", "0123456789"); // 10 bytes == limit → no rotate (> not >=)
    try cw.finalize();

    try std.testing.expectEqual(@as(u32, 1), cw.chunk_index);
}
