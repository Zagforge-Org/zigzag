const std = @import("std");

/// Helper function to print to stdout with a fixed buffer.
pub fn stdoutPrint(comptime fmt: []const u8, args: anytype) anyerror!void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print(fmt, args);
    try stdout.flush();
}
