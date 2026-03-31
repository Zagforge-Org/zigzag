const std = @import("std");

// Extern declarations matching chunker.h / tree_sitter/api.h
// Using opaque type for TSLanguage — we never inspect its internals.
const TSLanguage = opaque {};

const CChunk = extern struct {
    start_line: u32,
    end_line: u32,
};

const ChunkConfig = extern struct {
    node_types: [*c]const [*c]const u8,
    node_type_count: u32,
};

const ChunkResult = extern struct {
    chunks: [*c]CChunk,
    count: u32,
};

extern fn extract_chunks(language: *const TSLanguage, config: *const ChunkConfig, source: [*c]const u8, length: u32) ChunkResult;
extern fn free_chunk_result(result: ChunkResult) void;
extern fn tree_sitter_python() *const TSLanguage;
extern fn tree_sitter_javascript() *const TSLanguage;
extern fn tree_sitter_zig() *const TSLanguage;
extern fn tree_sitter_typescript() *const TSLanguage;
extern fn tree_sitter_tsx() *const TSLanguage;
extern fn tree_sitter_rust() *const TSLanguage;
extern fn tree_sitter_go() *const TSLanguage;

const python_types = [_][*c]const u8{
    "function_definition",
    "class_definition",
    "decorated_definition",
};

const javascript_types = [_][*c]const u8{
    "function_declaration",
    "class_declaration",
    "generator_function_declaration",
    "export_statement",
};

const zig_types = [_][*c]const u8{
    "function_declaration",
    "variable_declaration",
    "test_declaration",
};

const go_types = [_][*c]const u8{
    "function_declaration",
    "method_declaration",
    "type_declaration",
};

const rust_types = [_][*c]const u8{
    "function_item",
    "struct_item",
    "enum_item",
    "trait_item",
    "impl_item",
    "type_item",
};

const typescript_types = [_][*c]const u8{
    "function_declaration",
    "class_declaration",
    "interface_declaration",
    "type_alias_declaration",
    "enum_declaration",
    "export_statement",
};

pub const Chunk = struct {
    start_line: u32, // 0-based (tree-sitter row)
    end_line: u32, // 0-based, inclusive
};

const LanguageConfig = struct {
    language: *const TSLanguage,
    node_types: []const [*c]const u8,
};

fn languageConfig(ext: []const u8) ?LanguageConfig {
    // entry.extension always has a leading dot — strip it
    const e = if (ext.len > 0 and ext[0] == '.') ext[1..] else ext;
    if (std.mem.eql(u8, e, "py")) {
        return .{
            .language = tree_sitter_python(),
            .node_types = &python_types,
        };
    }
    if (std.mem.eql(u8, e, "js") or std.mem.eql(u8, e, "mjs") or std.mem.eql(u8, e, "cjs") or std.mem.eql(u8, e, "jsx")) {
        return .{
            .language = tree_sitter_javascript(),
            .node_types = &javascript_types,
        };
    }
    if (std.mem.eql(u8, e, "zig")) {
        return .{
            .language = tree_sitter_zig(),
            .node_types = &zig_types,
        };
    }
    if (std.mem.eql(u8, e, "go")) {
        return .{
            .language = tree_sitter_go(),
            .node_types = &go_types,
        };
    }
    if (std.mem.eql(u8, e, "rs")) {
        return .{
            .language = tree_sitter_rust(),
            .node_types = &rust_types,
        };
    }
    if (std.mem.eql(u8, e, "ts")) {
        return .{
            .language = tree_sitter_typescript(),
            .node_types = &typescript_types,
        };
    }
    if (std.mem.eql(u8, e, "tsx")) {
        return .{
            .language = tree_sitter_tsx(),
            .node_types = &typescript_types,
        };
    }
    return null;
}

/// Returns null if the extension is unsupported or no top-level chunks are found.
/// Caller owns the returned slice; free with allocator.free().
pub fn chunkSource(
    source: []const u8,
    ext: []const u8,
    allocator: std.mem.Allocator,
) !?[]Chunk {
    const lc = languageConfig(ext) orelse return null;

    const config = ChunkConfig{
        .node_types = @ptrCast(lc.node_types.ptr),
        .node_type_count = @intCast(lc.node_types.len),
    };

    const result = extract_chunks(
        lc.language,
        &config,
        source.ptr,
        @intCast(source.len),
    );
    defer free_chunk_result(result);

    if (result.count == 0) return null;

    const chunks = try allocator.alloc(Chunk, result.count);
    for (result.chunks[0..result.count], chunks) |raw, *out| {
        out.* = .{ .start_line = raw.start_line, .end_line = raw.end_line };
    }
    return chunks;
}
