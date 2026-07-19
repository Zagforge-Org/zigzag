const std = @import("std");
const Config = @import("../../commands/config/Config.zig");
const stdoutPrint = @import("../../../fs/stdout.zig").stdoutPrint;
pub const VERSION = @import("../../commands/config/Config.zig").VERSION;

/// printVersion prints version information to stdout.
pub fn printVersion(io: std.Io, cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    try stdoutPrint(io, version_fmt, .{cfg.version});
}

/// writeVersion writes version information to `w`. Separated from printVersion
/// so tests can exercise it against a buffer instead of the real stdout.
pub fn writeVersion(w: *std.Io.Writer, cfg: *Config) anyerror!void {
    try w.print(version_fmt, .{cfg.version});
}

const version_fmt =
    \\version {s}
    \\
;
