const std = @import("std");
const computeOutputSegment = @import("paths.zig").computeOutputSegment;
const deriveJsonPath = @import("paths.zig").deriveJsonPath;
const deriveHtmlPath = @import("paths.zig").deriveHtmlPath;
const deriveLlmPath = @import("paths.zig").deriveLlmPath;
const resolveOutputPath = @import("paths.zig").resolveOutputPath;

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

    var cfg = @import("../config/config.zig").Config.default(allocator);
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
