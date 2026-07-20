const std = @import("std");

/// Nanoseconds elapsed since `start` (from Timestamp.now(.real)). Clamped to 0.
pub inline fn nsElapsed(io: std.Io, start: i128) u64 {
    const delta = std.Io.Timestamp.now(io, .real).nanoseconds - start;
    return @intCast(@max(0, delta));
}
