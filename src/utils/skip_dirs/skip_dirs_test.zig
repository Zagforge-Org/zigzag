const std = @import("std");
const skip_dirs = @import("./skip_dirs.zig");

test "DEFAULT_SKIP_DIRS contains node_modules" {
    try expectContains("node_modules");
}

test "DEFAULT_SKIP_DIRS contains .git" {
    try expectContains(".git");
}

test "DEFAULT_SKIP_DIRS contains .cache" {
    try expectContains(".cache");
}

test "DEFAULT_SKIP_DIRS has no duplicate entries" {
    for (skip_dirs.DEFAULT_SKIP_DIRS, 0..) |a, i| {
        for (skip_dirs.DEFAULT_SKIP_DIRS, 0..) |b, j| {
            if (i != j) {
                try std.testing.expect(!std.mem.eql(u8, a, b));
            }
        }
    }
}

fn expectContains(needle: []const u8) !void {
    for (skip_dirs.DEFAULT_SKIP_DIRS) |entry| {
        if (std.mem.eql(u8, entry, needle)) return;
    }
    return error.NotFound;
}
