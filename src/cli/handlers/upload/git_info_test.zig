const std = @import("std");
const parseRepoFullName = @import("./git_info.zig").parseRepoFullName;

test "parseRepoFullName: HTTPS with .git suffix" {
    const allocator = std.testing.allocator;
    const name = try parseRepoFullName(allocator, "https://github.com/acme/myrepo.git");
    defer allocator.free(name);
    try std.testing.expectEqualStrings("acme/myrepo", name);
}

test "parseRepoFullName: HTTPS without .git suffix" {
    const allocator = std.testing.allocator;
    const name = try parseRepoFullName(allocator, "https://github.com/acme/myrepo");
    defer allocator.free(name);
    try std.testing.expectEqualStrings("acme/myrepo", name);
}

test "parseRepoFullName: HTTP (non-TLS) URL" {
    const allocator = std.testing.allocator;
    const name = try parseRepoFullName(allocator, "http://github.com/acme/myrepo.git");
    defer allocator.free(name);
    try std.testing.expectEqualStrings("acme/myrepo", name);
}

test "parseRepoFullName: SSH with .git suffix" {
    const allocator = std.testing.allocator;
    const name = try parseRepoFullName(allocator, "git@github.com:acme/myrepo.git");
    defer allocator.free(name);
    try std.testing.expectEqualStrings("acme/myrepo", name);
}

test "parseRepoFullName: SSH without .git suffix" {
    const allocator = std.testing.allocator;
    const name = try parseRepoFullName(allocator, "git@github.com:acme/myrepo");
    defer allocator.free(name);
    try std.testing.expectEqualStrings("acme/myrepo", name);
}

test "parseRepoFullName: org_slug derived correctly" {
    const allocator = std.testing.allocator;
    const name = try parseRepoFullName(allocator, "https://github.com/zagforge/zigzag.git");
    defer allocator.free(name);
    const slash = std.mem.indexOfScalar(u8, name, '/') orelse name.len;
    try std.testing.expectEqualStrings("zagforge", name[0..slash]);
    try std.testing.expectEqualStrings("zigzag", name[slash + 1 ..]);
}

test "parseRepoFullName: HTTPS missing path returns error" {
    const allocator = std.testing.allocator;
    const result = parseRepoFullName(allocator, "https://github.com");
    try std.testing.expectError(error.InvalidRemoteUrl, result);
}
