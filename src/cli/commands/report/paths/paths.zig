const std = @import("std");
const Config = @import("../../config/config.zig").Config;

/// Compute the output directory segment for a scanned path.
/// Relative paths have "./" stripped; absolute paths use basename only.
pub fn computeOutputSegment(path: []const u8) []const u8 {
    if (std.fs.path.isAbsolute(path)) {
        return std.fs.path.basename(path);
    }
    if (std.mem.startsWith(u8, path, "./")) {
        const stripped = path[2..];
        return if (stripped.len > 0) stripped else ".";
    }
    return if (path.len > 0) path else ".";
}

/// Resolve the full output file path for a given scanned path and filename.
/// Creates output directory tree if it doesn't exist.
/// Caller must free the returned slice.
pub fn resolveOutputPath(
    allocator: std.mem.Allocator,
    cfg: *const Config,
    scanned_path: []const u8,
    filename: []const u8,
) ![]u8 {
    const base_dir: []const u8 = if (cfg.output_dir) |d| d else "zigzag-reports";
    const segment = computeOutputSegment(scanned_path);
    const output_dir = try std.fs.path.join(allocator, &.{ base_dir, segment });
    defer allocator.free(output_dir);
    try std.fs.cwd().makePath(output_dir);
    return std.fs.path.join(allocator, &.{ output_dir, filename });
}

/// Derive a JSON output path from the markdown path by replacing the extension.
pub fn deriveJsonPath(allocator: std.mem.Allocator, md_path: []const u8) ![]u8 {
    if (std.mem.endsWith(u8, md_path, ".md")) {
        return std.fmt.allocPrint(allocator, "{s}.json", .{md_path[0 .. md_path.len - 3]});
    }
    return std.fmt.allocPrint(allocator, "{s}.json", .{md_path});
}

/// Derive an HTML output path from the markdown path by replacing the extension.
pub fn deriveHtmlPath(allocator: std.mem.Allocator, md_path: []const u8) ![]u8 {
    if (std.mem.endsWith(u8, md_path, ".md")) {
        return std.fmt.allocPrint(allocator, "{s}.html", .{md_path[0 .. md_path.len - 3]});
    }
    return std.fmt.allocPrint(allocator, "{s}.html", .{md_path});
}

/// Derives the LLM report path by replacing the .md extension with .llm.md.
pub fn deriveLlmPath(allocator: std.mem.Allocator, md_path: []const u8) ![]u8 {
    if (std.mem.endsWith(u8, md_path, ".md")) {
        const stem = md_path[0 .. md_path.len - 3];
        return std.fmt.allocPrint(allocator, "{s}.llm.md", .{stem});
    }
    return std.fmt.allocPrint(allocator, "{s}.llm.md", .{md_path});
}
