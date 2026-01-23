const std = @import("std");
const winMmap = @import("./mmap/windows/mmap.zig").WinMMap;
const unixMmap = @import("./mmap/unix/mmap.zig").UnixMMap;
const api = @import("../platform/windows/api.zig");
const Context = @import("../cli/context.zig").Context;
const TProcessChunk = @import("../cli/commands/writer.zig").TProcessChunk;

const SMALL_FILE_THRESHOLD: usize = 16 << 20; // 16 MiB (16 * 2^20)
const CHUNK_SIZE: usize = 8 << 10; // 64 KiB (64 * 2^10)
const MMAP_THRESHOLD: usize = 16 << 20; // 16 MiB

const FileError = error{
    NotAFile,
};

pub const ReadResult = union(enum) {
    Alloc: []u8,
    Mapped: MappedFile,
    Chunked: void,
};

pub const MappedFile = struct {
    data: []const u8,
    len: usize,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        if (self.len != 0 and self.data.len != 0) {
            const builtin = @import("builtin");
            switch (builtin.os.tag) {
                .windows => _ = {
                    const ptr: *anyopaque = @ptrCast(@constCast(self.data.ptr));
                    _ = api.UnmapViewOfFile(ptr);
                },
                else => _ = std.os.linux.munmap(self.data.ptr, self.len),
            }
            self.data = &[_]u8{};
            self.len = 0;
        }
    }
};

/// Check if a path is a file
pub fn isFile(path: []const u8) !bool {
    const stat = try std.fs.cwd().statFile(path);
    return stat.kind == .file;
}

/// Get the size of a file
pub fn getFileSize(path: []const u8) !u64 {
    const stat = try std.fs.cwd().statFile(path);
    if (stat.kind != .file) return FileError.NotAFile;
    return stat.size;
}

/// Read a file into memory
pub fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const file_size = (try file.stat()).size;
    return try file.readToEndAlloc(allocator, file_size);
}

/// Read a file in chunk
pub fn readFileChunked(path: []const u8, comptime process: TProcessChunk, ctx: *Context) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var buffer: [CHUNK_SIZE]u8 = undefined;

    while (true) {
        const bytes_read = try file.read(buffer[0..]);
        if (bytes_read == 0) break;
        try process(ctx, buffer[0..bytes_read]);
    }
}

/// Read a file into memory mapped (OS dependent)
pub fn readFileMapped(path: []const u8) !MappedFile {
    const builtin = @import("builtin");
    const native_os = builtin.os.tag;

    if (native_os == .windows) {
        const mapping = try winMmap.open(path);
        return MappedFile{
            .data = mapping.data,
            .len = mapping.data.len,
        };
    } else {
        const mapping = try unixMmap.open(path);
        return MappedFile{
            .data = mapping.data,
            .len = mapping.data.len,
        };
    }
}

/// Automatically choose best read strategy based on file size
pub fn readFileAuto(
    allocator: std.mem.Allocator,
    path: []const u8,
    process: TProcessChunk,
    ctx: *Context,
) !ReadResult {
    const size = try getFileSize(path);

    // Small files → read fully into memory
    if (size <= SMALL_FILE_THRESHOLD) {
        const data = try readFileAlloc(allocator, path);
        return .{ .Alloc = data };
    }

    // Medium files → memory map
    if (size <= MMAP_THRESHOLD) {
        const mapped = try readFileMapped(path);
        return .{ .Mapped = mapped };
    }

    // Very large files → stream in chunks
    try readFileChunked(path, process, ctx);
    return .{ .Chunked = {} };
}
