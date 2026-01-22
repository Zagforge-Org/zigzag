const std = @import("std");
const windows_api = @import("../../api/win.zig");
const windows = std.os.windows;

const FileError = error{
    EmptyFile,
    MapViewFailed,
    MMapFailed,
};

pub const WinMMap = struct {
    data: []const u8,
    mapping: ?windows.HANDLE,

    const Self = @This();

    pub fn open(path: []const u8) !Self {
        var file = try std.fs.cwd().openFile(path, .{});
        errdefer file.close();

        const size = try file.getEndPos();
        if (size == 0) return Self{ .data = &[_]u8{}, .mapping = null };

        const mapping = windows_api.CreateFileMappingW(
            file.handle,
            null,
            windows_api.PAGE_READONLY,
            @intCast(size >> 32),
            @intCast(size & 0xffffffff),
            null,
        );

        if (@intFromPtr(mapping) == 0 or mapping == windows.INVALID_HANDLE_VALUE) {
            return error.MMapFailed;
        }

        const view = windows_api.MapViewOfFile(
            mapping,
            windows_api.FILE_MAP_READ,
            0,
            0,
            0,
        );
        // if (view == null) return error.MapViewFailed;
        if (@intFromPtr(view) == 0) {
            _ = windows_api.CloseHandle(mapping);
            return error.MapViewFailed;
        }

        const bytes = @as([*]const u8, @ptrCast(view.?))[0..@intCast(size)];

        return Self{
            .data = bytes,
            .mapping = mapping,
        };
    }

    pub fn close(self: *WinMMap) !void {
        if (self.data.len != 0) {
            _ = windows_api.UnmapViewOfFile(self.data.ptr);
            self.data = &[_]u8{};
        }
        if (self.mapping != null) {
            _ = windows_api.CloseHandle(self.mapping);
            self.mapping = null;
        }
    }
};
