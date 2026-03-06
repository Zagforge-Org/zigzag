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

// ============================================================
// Tests
// ============================================================

test "computeOutputSegment strips leading ./" {
    try std.testing.expectEqualStrings("src", computeOutputSegment("./src"));
    try std.testing.expectEqualStrings("src/cli", computeOutputSegment("./src/cli"));
}

test "computeOutputSegment uses basename for absolute paths" {
    try std.testing.expectEqualStrings("src", computeOutputSegment("/home/user/project/src"));
}

test "computeOutputSegment returns path unchanged when no ./ prefix" {
    try std.testing.expectEqualStrings("src", computeOutputSegment("src"));
}

test "computeOutputSegment handles bare dot" {
    try std.testing.expectEqualStrings(".", computeOutputSegment("."));
    try std.testing.expectEqualStrings(".", computeOutputSegment("./"));
}

test "deriveJsonPath replaces .md extension with .json" {
    const alloc = std.testing.allocator;
    const result = try deriveJsonPath(alloc, "report.md");
    defer alloc.free(result);
    try std.testing.expectEqualStrings("report.json", result);
}

test "deriveJsonPath handles full path with .md extension" {
    const alloc = std.testing.allocator;
    const result = try deriveJsonPath(alloc, "/some/dir/output.md");
    defer alloc.free(result);
    try std.testing.expectEqualStrings("/some/dir/output.json", result);
}

test "deriveJsonPath appends .json when no .md extension" {
    const alloc = std.testing.allocator;
    const result = try deriveJsonPath(alloc, "output.txt");
    defer alloc.free(result);
    try std.testing.expectEqualStrings("output.txt.json", result);
}

test "deriveHtmlPath replaces .md extension with .html" {
    const alloc = std.testing.allocator;
    const result = try deriveHtmlPath(alloc, "report.md");
    defer alloc.free(result);
    try std.testing.expectEqualStrings("report.html", result);
}

test "deriveHtmlPath handles full path with .md extension" {
    const alloc = std.testing.allocator;
    const result = try deriveHtmlPath(alloc, "/some/dir/output.md");
    defer alloc.free(result);
    try std.testing.expectEqualStrings("/some/dir/output.html", result);
}

test "deriveHtmlPath appends .html when no .md extension" {
    const alloc = std.testing.allocator;
    const result = try deriveHtmlPath(alloc, "output.txt");
    defer alloc.free(result);
    try std.testing.expectEqualStrings("output.txt.html", result);
}

test "deriveLlmPath replaces .md extension with .llm.md" {
    const result = try deriveLlmPath(std.testing.allocator, "zigzag-reports/src/report.md");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("zigzag-reports/src/report.llm.md", result);
}

test "deriveLlmPath appends .llm.md when no .md extension" {
    const result = try deriveLlmPath(std.testing.allocator, "zigzag-reports/src/report");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("zigzag-reports/src/report.llm.md", result);
}

test "resolveOutputPath returns path under configured output_dir" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_abs = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_abs);

    var cfg = @import("../../config/config.zig").Config.default(allocator);
    defer cfg.deinit();
    cfg.output_dir = try allocator.dupe(u8, tmp_abs);
    cfg._output_dir_allocated = true;

    const result = try resolveOutputPath(allocator, &cfg, "./src", "report.md");
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "src") != null);
    try std.testing.expect(std.mem.endsWith(u8, result, "report.md"));
    tmp.dir.access("src", .{}) catch |err| {
        std.debug.print("Expected 'src' dir to exist in tmp, got: {s}\n", .{@errorName(err)});
        return err;
    };
}
