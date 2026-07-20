const std = @import("std");
const ast_chunker = @import("ast_chunker.zig");

test "chunkSource returns null for unsupported extension" {
    const result = try ast_chunker.chunkSource("fn main() {}", ".go", std.testing.allocator);
    try std.testing.expectEqual(@as(?[]ast_chunker.Chunk, null), result);
}

test "chunkSource returns null for empty Python source" {
    const result = try ast_chunker.chunkSource("", ".py", std.testing.allocator);
    try std.testing.expectEqual(@as(?[]ast_chunker.Chunk, null), result);
}

test "chunkSource returns null for Python source with no top-level definitions" {
    const source = "x = 1\ny = 2\n";
    const result = try ast_chunker.chunkSource(source, ".py", std.testing.allocator);
    try std.testing.expectEqual(@as(?[]ast_chunker.Chunk, null), result);
}

test "chunkSource returns chunks for Python functions" {
    const source =
        \\def hello():
        \\    pass
        \\
        \\def world():
        \\    pass
        \\
    ;
    const chunks = try ast_chunker.chunkSource(source, ".py", std.testing.allocator) orelse
        return error.ExpectedChunks;
    defer std.testing.allocator.free(chunks);

    try std.testing.expectEqual(@as(usize, 2), chunks.len);
    // tree-sitter rows are 0-based
    try std.testing.expectEqual(@as(u32, 0), chunks[0].start_line);
    try std.testing.expectEqual(@as(u32, 1), chunks[0].end_line);
    try std.testing.expectEqual(@as(u32, 3), chunks[1].start_line);
    try std.testing.expectEqual(@as(u32, 4), chunks[1].end_line);
}

test "chunkSource returns chunks for Python class" {
    const source =
        \\class Foo:
        \\    def bar(self):
        \\        pass
        \\
    ;
    const chunks = try ast_chunker.chunkSource(source, ".py", std.testing.allocator) orelse
        return error.ExpectedChunks;
    defer std.testing.allocator.free(chunks);

    try std.testing.expectEqual(@as(usize, 1), chunks.len);
    try std.testing.expectEqual(@as(u32, 0), chunks[0].start_line);
    try std.testing.expectEqual(@as(u32, 2), chunks[0].end_line);
}
