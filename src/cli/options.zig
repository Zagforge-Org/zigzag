const std = @import("std");
const Config = @import("./commands/config.zig").Config;
const handler = @import("handlers.zig");

///  OptionHandler represents a command-line option.
pub const OptionHandler = struct {
    name: []const u8,
    takes_value: bool,
    handler: *const fn (*Config, std.mem.Allocator, ?[]const u8) anyerror!void,
};

pub const options = [_]OptionHandler{
    .{ .name = "--version", .takes_value = false, .handler = &handler.printVersion },
    .{ .name = "--help", .takes_value = false, .handler = &handler.printHelp },
    .{ .name = "--skip-cache", .takes_value = false, .handler = &handler.handleSkipCache },
    .{ .name = "--small", .takes_value = true, .handler = &handler.handleSmall },
    .{ .name = "--mmap", .takes_value = true, .handler = &handler.handleMmap },
    .{ .name = "--path", .takes_value = true, .handler = &handler.handlePath },
    .{ .name = "--ignore", .takes_value = true, .handler = &handler.handleIgnore },
    .{ .name = "--timezone", .takes_value = true, .handler = &handler.handleTimezone },
    .{ .name = "--watch", .takes_value = false, .handler = &handler.handleWatch },
    .{ .name = "--output", .takes_value = true, .handler = &handler.handleOutput },
    .{ .name = "--json", .takes_value = false, .handler = &handler.handleJson },
    .{ .name = "--html", .takes_value = false, .handler = &handler.handleHtml },
};
