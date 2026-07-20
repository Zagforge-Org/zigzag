const std = @import("std");
const time = @import("./time.zig");

test "nsElapsed clamps future timestamp to 0" {
    const future = std.Io.Timestamp.now(std.testing.io, .real).nanoseconds + 1_000_000_000_000;
    try std.testing.expectEqual(@as(u64, 0), time.nsElapsed(std.testing.io, future));
}

test "nsElapsed returns positive for past timestamp" {
    const past = std.Io.Timestamp.now(std.testing.io, .real).nanoseconds - 1_000_000;
    try std.testing.expect(time.nsElapsed(std.testing.io, past) > 0);
}
