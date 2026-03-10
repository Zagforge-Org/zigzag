const std = @import("std");
const sse = @import("sse.zig");
const JobEntry = @import("../../../../../jobs/entry.zig").JobEntry;

test "buildFileDeltaPayload file_update contains type, path, content" {
    const alloc = std.testing.allocator;
    const entry = JobEntry{
        .path = "src/main.zig",
        .content = @constCast("const x = 1;"),
        .size = 12,
        .mtime = 0,
        .extension = ".zig",
        .line_count = 1,
    };
    const payload = try sse.buildFileDeltaPayload(alloc, &entry, .updated);
    defer alloc.free(payload);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, payload, .{});
    defer parsed.deinit();

    try std.testing.expectEqualStrings("file_update", parsed.value.object.get("type").?.string);
    try std.testing.expectEqualStrings("src/main.zig", parsed.value.object.get("path").?.string);
    try std.testing.expectEqualStrings("const x = 1;", parsed.value.object.get("content").?.string);
}

test "buildFileDeletePayload file_delete contains type and path only" {
    const alloc = std.testing.allocator;
    const payload = try sse.buildFileDeletePayload(alloc, "src/deleted.zig");
    defer alloc.free(payload);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, payload, .{});
    defer parsed.deinit();

    try std.testing.expectEqualStrings("file_delete", parsed.value.object.get("type").?.string);
    try std.testing.expectEqualStrings("src/deleted.zig", parsed.value.object.get("path").?.string);
    try std.testing.expect(parsed.value.object.get("content") == null);
}
