const std = @import("std");
const sections = @import("sections.zig");
const Chunk = @import("../ast/ast_chunker.zig").Chunk;

// AST path: sig_end_byte > start_byte is exact byte slice, trailing whitespace trimmed.
test "signatureSlice cuts at the AST body boundary" {
    const content = "pub fn foo(a: u32) void {\n    return;\n}\n";
    const brace: u32 = @intCast(std.mem.indexOfScalar(u8, content, '{').?);
    const chunk = Chunk{ .start_line = 0, .end_line = 2, .start_byte = 0, .sig_end_byte = brace };
    try std.testing.expectEqualStrings("pub fn foo(a: u32) void", sections.signatureSlice(content, chunk));
}

// The slice must start at start_byte, not at byte 0 of the buffer.
test "signatureSlice honors start_byte for declarations not at file start" {
    const content = "// header\npub fn bar() void {\n}\n";
    const start: u32 = @intCast(std.mem.indexOf(u8, content, "pub").?);
    const brace: u32 = @intCast(std.mem.indexOfScalar(u8, content, '{').?);
    const chunk = Chunk{ .start_line = 1, .end_line = 2, .start_byte = start, .sig_end_byte = brace };
    try std.testing.expectEqualStrings("pub fn bar() void", sections.signatureSlice(content, chunk));
}

// Fallback path (no AST body: sig_end_byte == start_byte), stop at the first `;`.
test "signatureSlice falls back to first terminator for body-less decls" {
    const content = "const std = @import(\"std\");\n";
    const chunk = Chunk{ .start_line = 0, .end_line = 0, .start_byte = 0, .sig_end_byte = 0 };
    try std.testing.expectEqualStrings("const std = @import(\"std\");", sections.signatureSlice(content, chunk));
}

// Fallback path with a brace (e.g. a grammar without a `body` field), stop at the first `{`.
test "signatureSlice fallback stops at the first brace" {
    const content = "fun greet() {\n}\n";
    const chunk = Chunk{ .start_line = 0, .end_line = 1, .start_byte = 0, .sig_end_byte = 0 };
    try std.testing.expectEqualStrings("fun greet() {", sections.signatureSlice(content, chunk));
}
