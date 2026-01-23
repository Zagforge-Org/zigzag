const std = @import("std");
const FileError = @import("../common.zig").FileError;

pub const UnixMMap = struct {
    const Self = @This();
    data: []u8,

    pub fn open(path: []const u8) !Self {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const file_size = (try file.stat()).size;

        if (file_size == 0) return Self{
            .data = &[_]u8{},
        };

        const os = std.os;
        const fd = file.handle;

        const flags: os.linux.MAP = .{
            .TYPE = .PRIVATE,
        };

        const file_size_usize = @as(usize, file_size);
        const prot = os.linux.PROT.READ;
        const data_addr = os.linux.mmap(null, file_size_usize, prot, flags, @intCast(fd), 0);

        if (@as(isize, @bitCast(data_addr)) < 0) {
            std.log.err("mmap failed with error code: {}", .{-@as(isize, @bitCast(data_addr))});
            return error.MMapFailed;
        }

        // Create slice from the pointer
        const data_ptr: [*]u8 = @ptrFromInt(data_addr);
        const data_slice: []u8 = data_ptr[0..file_size_usize];

        return Self{
            .data = data_slice,
        };
    }

    pub fn close(self: *Self) !void {
        if (self.data.len != 0) {
            const os = std.os;
            _ = os.linux.munmap(self.data.ptr, self.data.len);
            self.data = &[_]u8{};
        }
    }
};
