const std = @import("std");
const Config = @import("config.zig").Config;

pub fn printVersion(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;

    std.debug.print(
        \\ai-proj
        \\version {s}
        \\
    , .{cfg.version});
}

pub fn printHelp(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = cfg;
    _ = allocator;
    _ = value;

    std.debug.print(
        \\Usage: ai-proj [OPTIONS]
        \\
        \\Options:
        \\  --help                 Print this help message
        \\  --path <path>           Path to the project directory (default: current directory)
        \\  --version              Print version information
        \\  --ignore <pattern>     Ignore files matching the given pattern
        \\  --skip-git             Skip git operations
        \\  --skip-cache           Skip cache operations
        \\  --strategy             Print strategy
        \\  --small <bytes>        Small threshold (default: 1 MiB)
        \\  --mmap <bytes>         Mmap threshold (default: 16 MiB)
        \\
    , .{});
}

pub fn handleIgnore(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    cfg.ignore_patterns = value.?;
}

pub fn handlePath(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    cfg.path = value.?;
}

// pub fn handleSkipGit(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
//     _ = allocator;
//     _ = value;
//     cfg.skip_git = true;
// }

pub fn handleSkipCache(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    cfg.skip_cache = true;
}

// pub fn handleStrategy(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
//     _ = allocator;
//     _ = value;
//     // cfg.print_strategy = true;
// }

pub fn handleSmall(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    if (value) |v| {
        cfg.small_threshold = try std.fmt.parseInt(usize, v, 10);
    }
}

pub fn handleMmap(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    if (value) |v| {
        cfg.mmap_threshold = try std.fmt.parseInt(usize, v, 10);
    }
}
