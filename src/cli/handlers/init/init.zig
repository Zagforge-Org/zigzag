const std = @import("std");

const DEFAULT_CONF_FILENAME = @import("../../../conf/file.zig").DEFAULT_CONF_FILENAME;
const FileConf = @import("../../../conf/file.zig").FileConf;
const lg = @import("../../../utils/utils.zig");

/// handleInit creates the zig.conf.json configuration file with default values.
/// dir is the directory in which to create the file (use std.fs.cwd() for normal use).
pub fn handleInit(allocator: std.mem.Allocator, dir: std.fs.Dir) anyerror!void {
    const file = dir.createFile(DEFAULT_CONF_FILENAME, .{
        .read = true,
        .exclusive = true,
    }) catch |err| switch (err) {
        error.PathAlreadyExists => {
            const content = try dir.readFileAlloc(allocator, DEFAULT_CONF_FILENAME, 1 << 20);
            defer allocator.free(content);
            if (FileConf.isEmpty(content)) {
                const f = try dir.createFile(DEFAULT_CONF_FILENAME, .{});
                defer f.close();
                var buf: [1024]u8 = undefined;
                var w = f.writer(&buf);
                try w.interface.writeAll(FileConf.default());
                try w.interface.flush();
                return;
            }
            lg.printWarn("{s} already exists", .{DEFAULT_CONF_FILENAME});
            return;
        },
        else => return err,
    };
    defer file.close();

    var buf: [1024]u8 = undefined;
    var w = file.writer(&buf);
    try w.interface.writeAll(FileConf.default());
    try w.interface.flush();
    lg.printSuccess("Created {s}", .{DEFAULT_CONF_FILENAME});
}
