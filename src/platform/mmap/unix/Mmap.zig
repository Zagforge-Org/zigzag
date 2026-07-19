//! A memory-mapped file on Unix-like systems.

const std = @import("std");

const Self = @This();

data: []u8,

pub fn open(io: std.Io, path: []const u8) !Self {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    const file_size = (try file.stat(io)).size;
    if (file_size == 0) return .{ .data = &[_]u8{} };

    const os = std.os;
    const fd = file.handle;

    const flags: os.linux.MAP = .{ .TYPE = .PRIVATE };
    const file_size_usize = @as(usize, file_size);
    const prot = os.linux.PROT.READ;
    const data_addr = os.linux.mmap(null, file_size_usize, prot, flags, @intCast(fd), 0);

    if (@as(isize, @bitCast(data_addr)) < 0) {
        std.log.err("mmap failed with error code: {}", .{-@as(isize, @bitCast(data_addr))});
        return error.MMapFailed;
    }

    const data_ptr: [*]u8 = @ptrFromInt(data_addr);
    return .{ .data = data_ptr[0..file_size_usize] };
}

pub fn close(self: *Self) !void {
    if (self.data.len != 0) {
        _ = std.os.linux.munmap(self.data.ptr, self.data.len);
        self.data = &[_]u8{};
    }
}
