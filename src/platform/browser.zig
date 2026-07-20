//! Open a URL in the system browser, dispatched per platform.

const std = @import("std");
const builtin = @import("builtin");

/// Launch the OS browser for `url` and reap the child. Fire-and-forget: any error
/// is ignored.
pub fn openUrl(io: std.Io, allocator: std.mem.Allocator, url: []const u8) void {
    const argv: []const []const u8 = switch (comptime builtin.os.tag) {
        .macos => &.{ "open", url },
        .windows => &.{ "cmd", "/C", "start", "", url },
        else => &.{ "xdg-open", url },
    };
    const result = std.process.run(allocator, io, .{ .argv = argv }) catch return;
    allocator.free(result.stdout);
    allocator.free(result.stderr);
}
