const std = @import("std");
const writeHelp = @import("./help.zig").writeHelp;

test "writeHelp writes usage text" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try writeHelp(&aw.writer);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), "Usage: zigzag") != null);
}
