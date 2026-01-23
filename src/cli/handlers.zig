const std = @import("std");
const Config = @import("./commands/config.zig").Config;

/// printVersion prints version information.
pub fn printVersion(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    std.debug.print(
        \\zig-zag
        \\version {s}
        \\
    , .{cfg.version});
}

/// printHelp prints help information.
pub fn printHelp(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = cfg;
    _ = allocator;
    _ = value;
    std.debug.print(
        \\Usage: zig-zag [OPTIONS]
        \\
        \\Options:
        \\  --help        Print this help message
        \\  --path        Path to a project directory (can be used multiple times)
        \\  --version     Print version information
        \\  --ignore      Ignore files matching the given pattern
        \\  --skip-git    Skip git operations
        \\  --skip-cache  Skip cache operations
        \\  --strategy    Print strategy
        \\  --small       Small threshold (default: 1 MiB)
        \\  --mmap        Mmap threshold (default: 16 MiB)
        \\
        \\Examples:
        \\  zig-zag --path ./project1 --path ./project2
        \\  zig-zag --path ./src --ignore "*.test.zig"
        \\
    , .{});
}

/// handleIgnore handles the ignore option.
pub fn handleIgnore(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    cfg.ignore_patterns = value.?;
}

/// handlePath handles the path option (can be called multiple times).
pub fn handlePath(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    if (value) |path| {
        const owned_path = try allocator.dupe(u8, path);
        try cfg.paths.append(allocator, owned_path);
    }
}

/// handleSkipCache handles the skip-cache option.
pub fn handleSkipCache(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    cfg.skip_cache = true;
}

/// handleSmall handles the small option.
pub fn handleSmall(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    if (value) |v| {
        cfg.small_threshold = try std.fmt.parseInt(usize, v, 10);
    }
}

/// handleMmap handles the mmap option.
pub fn handleMmap(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    if (value) |v| {
        cfg.mmap_threshold = try std.fmt.parseInt(usize, v, 10);
    }
}
