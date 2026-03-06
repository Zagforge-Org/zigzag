const std = @import("std");
const isBoilerplate = @import("./content.zig").isBoilerplate;
const getCommentPrefix = @import("./content.zig").getCommentPrefix;
const condenseContent = @import("./content.zig").condenseContent;

test "isBoilerplate detects exact filenames" {
    try std.testing.expect(isBoilerplate("package-lock.json"));
    try std.testing.expect(isBoilerplate("go.sum"));
    try std.testing.expect(isBoilerplate("yarn.lock"));
    try std.testing.expect(!isBoilerplate("main.zig"));
}

test "isBoilerplate detects .min.js extension" {
    try std.testing.expect(isBoilerplate("jquery.min.js"));
    try std.testing.expect(!isBoilerplate("app.js"));
}

test "isBoilerplate detects .generated. suffix" {
    try std.testing.expect(isBoilerplate("proto.generated.go"));
    try std.testing.expect(!isBoilerplate("generated.zig"));
}

test "getCommentPrefix returns correct prefix for known extensions" {
    try std.testing.expectEqualStrings("//", getCommentPrefix(".zig").?);
    try std.testing.expectEqualStrings("#", getCommentPrefix(".py").?);
    try std.testing.expectEqualStrings("--", getCommentPrefix(".sql").?);
    try std.testing.expectEqualStrings("%", getCommentPrefix(".tex").?);
    try std.testing.expect(getCommentPrefix(".md") == null);
    try std.testing.expect(getCommentPrefix(".unknown") == null);
}

test "condenseContent strips single-line comments" {
    const content =
        \\pub fn main() void {
        \\// this is a comment
        \\    const x = 1;
        \\}
    ;
    const result = try condenseContent(std.testing.allocator, content, ".zig", 150);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "// this is a comment") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "const x = 1") != null);
}

test "condenseContent collapses consecutive blank lines" {
    const content = "line1\n\n\nline2\n";
    const result = try condenseContent(std.testing.allocator, content, ".zig", 150);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "\n\n\n") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "line1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "line2") != null);
}

test "condenseContent truncates long files with correct omitted count" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const w = fbs.writer();
    for (0..100) |i| {
        try w.print("line {d}\n", .{i});
    }
    const content = fbs.getWritten();
    const result = try condenseContent(std.testing.allocator, content, ".md", 90);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "// [20 lines omitted]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "line 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "line 99") != null);
}

test "condenseContent returns full content when under max_lines" {
    const content = "line1\nline2\nline3\n";
    const result = try condenseContent(std.testing.allocator, content, ".zig", 150);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("line1\nline2\nline3\n", result);
}
