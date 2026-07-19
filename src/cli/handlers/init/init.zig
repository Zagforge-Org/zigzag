const std = @import("std");

const DEFAULT_CONF_FILENAME = @import("../../../conf/file.zig").DEFAULT_CONF_FILENAME;
const FileConf = @import("../../../conf/file.zig").FileConf;
const log = @import("../../../utils/logger/Logger.zig");

/// handleInit creates the zig.conf.json configuration file with default values.
/// dir is the directory in which to create the file (use std.Io.Dir.cwd() for normal use).
pub fn handleInit(io: std.Io, allocator: std.mem.Allocator, dir: std.Io.Dir) anyerror!void {
    const file = dir.createFile(io, DEFAULT_CONF_FILENAME, .{
        .read = true,
        .exclusive = true,
    }) catch |err| switch (err) {
        error.PathAlreadyExists => {
            const content = try dir.readFileAlloc(io, DEFAULT_CONF_FILENAME, allocator, .limited(1 << 20));
            defer allocator.free(content);
            if (FileConf.isEmpty(content)) {
                const f = try dir.createFile(io, DEFAULT_CONF_FILENAME, .{});
                defer f.close(io);
                var buf: [1024]u8 = undefined;
                var w = f.writer(io, &buf);
                try w.interface.writeAll(FileConf.default());
                try w.interface.flush();
                return;
            }
            log.warn(io, "{s} already exists", .{DEFAULT_CONF_FILENAME});
            return;
        },
        else => return err,
    };
    defer file.close(io);

    var buf: [1024]u8 = undefined;
    var w = file.writer(io, &buf);
    try w.interface.writeAll(FileConf.default());
    try w.interface.flush();
    log.success(io, "Created {s}", .{DEFAULT_CONF_FILENAME});
}
