const std = @import("std");

/// Returns true if the filename matches known boilerplate patterns.
pub fn isBoilerplate(filename: []const u8) bool {
    const boilerplate_exact = [_][]const u8{
        "package-lock.json",
        "go.sum",
        "yarn.lock",
        "Cargo.lock",
        "Gemfile.lock",
        "poetry.lock",
        "pnpm-lock.yaml",
        "composer.lock",
    };
    for (boilerplate_exact) |name| {
        if (std.mem.eql(u8, filename, name)) return true;
    }
    const boilerplate_ext = [_][]const u8{ ".lock", ".min.js", ".pb.go" };
    for (boilerplate_ext) |ext| {
        if (std.mem.endsWith(u8, filename, ext)) return true;
    }
    if (std.mem.indexOf(u8, filename, ".generated.") != null) return true;
    return false;
}

/// Returns the single-line comment prefix for the given file extension, or null if unknown.
pub fn getCommentPrefix(extension: []const u8) ?[]const u8 {
    const slash_slash = [_][]const u8{ ".zig", ".js", ".ts", ".jsx", ".tsx", ".rs", ".go", ".c", ".h", ".cpp", ".cc", ".java", ".swift", ".kt", ".cs" };
    for (slash_slash) |ext| {
        if (std.mem.eql(u8, extension, ext)) return "//";
    }
    const hash = [_][]const u8{ ".py", ".sh", ".rb", ".pl", ".r", ".yaml", ".yml", ".toml" };
    for (hash) |ext| {
        if (std.mem.eql(u8, extension, ext)) return "#";
    }
    const dash_dash = [_][]const u8{ ".sql", ".lua" };
    for (dash_dash) |ext| {
        if (std.mem.eql(u8, extension, ext)) return "--";
    }
    if (std.mem.eql(u8, extension, ".tex")) return "%";
    return null;
}

/// Condenses file content for LLM ingestion:
/// - Strips single-line comments (by extension)
/// - Collapses consecutive blank lines to 1
/// - Truncates files over max_lines to first 60 + last 20 lines
/// Returns caller-owned slice.
pub fn condenseContent(
    allocator: std.mem.Allocator,
    content: []const u8,
    extension: []const u8,
    max_lines: u64,
) ![]u8 {
    const comment_prefix = getCommentPrefix(extension);

    // Phase 1: comment strip + blank collapse
    var condensed: std.ArrayList([]const u8) = .empty;
    defer condensed.deinit(allocator);

    var prev_blank = false;
    var iter = std.mem.splitScalar(u8, content, '\n');
    while (iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        if (comment_prefix) |pfx| {
            if (std.mem.startsWith(u8, trimmed, pfx)) continue;
        }

        const is_blank = trimmed.len == 0;
        if (is_blank) {
            if (prev_blank) continue;
            prev_blank = true;
        } else {
            prev_blank = false;
        }

        try condensed.append(allocator, line);
    }

    // Phase 2: truncation
    // A trailing empty string from splitting a newline-terminated file is not
    // a real line; exclude it from the count but preserve it for the join so
    // that the output retains a trailing newline.
    const has_trailing_empty = condensed.items.len > 0 and
        condensed.items[condensed.items.len - 1].len == 0;
    const real_lines: u64 = @intCast(if (has_trailing_empty) condensed.items.len - 1 else condensed.items.len);
    const head: usize = 60;
    const tail: usize = 20;
    if (real_lines <= max_lines or real_lines <= head + tail) {
        return std.mem.join(allocator, "\n", condensed.items);
    }
    const total = real_lines;
    const omitted = total - (head + tail);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    const writer = out.writer(allocator);

    for (condensed.items[0..head]) |line| {
        try writer.writeAll(line);
        try writer.writeByte('\n');
    }

    try writer.print("// [{d} lines omitted]\n", .{omitted});

    const real_items = if (has_trailing_empty)
        condensed.items[0 .. condensed.items.len - 1]
    else
        condensed.items;
    const start_tail = real_items.len - tail;
    for (real_items[start_tail..]) |line| {
        try writer.writeAll(line);
        try writer.writeByte('\n');
    }

    return out.toOwnedSlice(allocator);
}
