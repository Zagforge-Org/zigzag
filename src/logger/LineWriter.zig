const std = @import("std");

const Self = @This();

buf: []u8,
pos: usize = 0,

pub fn init(buf: []u8) Self {
    return .{ .buf = buf };
}

pub fn write(self: *Self, text: []const u8) void {
    if (self.pos + text.len > self.buf.len)
        return;

    @memcpy(
        self.buf[self.pos..][0..text.len],
        text,
    );

    self.pos += text.len;
}

pub fn writeFmt(
    self: *Self,
    comptime fmt: []const u8,
    args: anytype,
) void {
    const result = std.fmt.bufPrint(
        self.buf[self.pos..],
        fmt,
        args,
    ) catch return;

    self.pos += result.len;
}

pub fn pad(self: *Self, amount: usize) void {
    var i: usize = 0;

    while (i < amount and self.pos < self.buf.len) : (i += 1) {
        self.buf[self.pos] = ' ';
        self.pos += 1;
    }
}

pub fn slice(self: *Self) []u8 {
    return self.buf[0..self.pos];
}
