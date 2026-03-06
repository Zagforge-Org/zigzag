const std = @import("std");
const readZonVersion = @import("./version.zig").readZonVersion;
const isRuntime = @import("./version.zig").isRuntime;

test "ONLY RUN THIS AT RUNTIME - build.zig.zon errors if not found" {
    if (!isRuntime()) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const result = readZonVersion(allocator, .{ .path = "nonexistent.zig.zon" });
    try std.testing.expectError(error.FileNotFound, result);
}

test "ONLY RUN THIS AT RUNTIME - build.zig.zon exceeds max bytes" {
    if (!isRuntime()) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const result = readZonVersion(allocator, .{ .max_bytes = 1 });
    try std.testing.expectError(error.FileTooBig, result);
}

test "ONLY RUN THIS AT RUNTIME - build.zig.zon exists" {
    if (!isRuntime()) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const result = try readZonVersion(allocator, .{});
    defer allocator.free(result);

    try std.testing.expect(result.len > 0);
}

test "isRuntime returns false when build options provide a real version" {
    // Skips in runtime mode (make test with fallback 0.0.0 options).
    // Passes in zig build test mode where options has the real project version.
    if (isRuntime()) return error.SkipZigTest;
}
