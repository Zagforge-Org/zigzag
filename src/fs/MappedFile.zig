const std = @import("std");
const builtin = @import("builtin");
const api = @import("../platform/windows/api.zig");
const Self = @This();

data: []const u8,
len: usize,

pub fn deinit(self: *Self) void {
    if (self.len != 0 and self.data.len != 0) {
        switch (builtin.os.tag) {
            .windows => {
                const ptr: *anyopaque = @ptrCast(@constCast(self.data.ptr));
                _ = api.UnmapViewOfFile(ptr);
            },
            else => _ = std.os.linux.munmap(self.data.ptr, self.len),
        }
        self.data = &[_]u8{};
        self.len = 0;
    }
}
