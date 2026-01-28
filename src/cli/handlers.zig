const std = @import("std");
const Config = @import("./commands/config.zig").Config;
const testing = std.testing;
const colorCode = @import("colors.zig").colorCode;
const colors = @import("colors.zig");
const VERSION = @import("../cli/commands/config.zig").VERSION;
const ascii_logo = @import("logo.zig").ascii_logo;
const stdoutPrint = @import("../fs/stdout.zig").stdoutPrint;

pub const TimezoneError = error{
    InvalidTimezoneMinutes,
    InvalidTimezoneHours,
};

fn makeTestConfig(allocator: std.mem.Allocator) Config {
    return Config.initDefault(allocator);
}

pub fn printAsciiLogo() anyerror!void {
    try stdoutPrint("{s}{s}{s}", .{
        colors.colorCode(colors.Color.Yellow),
        ascii_logo,
        colors.colorCode(colors.Color.Reset),
    });
}

/// printVersion prints version information.
pub fn printVersion(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;

    try stdoutPrint(
        \\{s}{s}{s}
        \\version {s}
        \\
    , .{
        colors.colorCode(colors.Color.Yellow),
        ascii_logo,
        colors.colorCode(colors.Color.Reset),
        cfg.version,
    });
}

test "printVersion should print version information" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try testing.expectEqualStrings(VERSION, cfg.version);
}

/// printHelp prints help information.
pub fn printHelp(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = cfg;
    _ = allocator;
    _ = value;

    try stdoutPrint(
        \\Usage: zigzag [OPTIONS]
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
        \\  --timezone    Timezone offset from UTC (e.g., +1, -5, +5:30)
        \\
        \\Examples:
        \\  zigzag --path ./project1 --path ./project2
        \\  zigzag --path ./src --ignore "*.test.zig"
        \\  zigzag --path ./src --timezone +1
        \\
    , .{});
}

test "printHelp runs without error" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    // This will print the help message to your console during 'zig test'
    try printHelp(&cfg, allocator, null);
}

/// handleIgnore handles the ignore option.
pub fn handleIgnore(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    cfg.ignore_patterns = value.?;
}

test "handleIgnore handles ignore option" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleIgnore(&cfg, allocator, "ignore_pattern");
    try testing.expectEqualStrings("ignore_pattern", cfg.ignore_patterns);
}

/// handlePath handles the path option (can be called multiple times).
pub fn handlePath(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    if (value) |path| {
        const owned_path = try allocator.dupe(u8, path);
        try cfg.paths.append(allocator, owned_path);
    }
}

test "handlePath handles path option" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handlePath(&cfg, allocator, "path");
    try testing.expectEqualStrings("path", cfg.paths.items[0]);
}

/// handleSkipCache handles the skip-cache option.
pub fn handleSkipCache(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    cfg.skip_cache = true;
}

test "handleSkipCache handles skip-cache option" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleSkipCache(&cfg, allocator, null);
    try testing.expectEqual(true, cfg.skip_cache);
}

/// handleSmall handles the small option.
pub fn handleSmall(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    if (value) |v| {
        cfg.small_threshold = try std.fmt.parseInt(usize, v, 10);
    }
}

test "handleSmall handles small option" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleSmall(&cfg, allocator, "1024");
    try testing.expectEqual(1024, cfg.small_threshold);
}

/// handleMmap handles the mmap option.
pub fn handleMmap(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    if (value) |v| {
        cfg.mmap_threshold = try std.fmt.parseInt(usize, v, 10);
    }
}

test "handleMmap handles mmap option" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleMmap(&cfg, allocator, "2048");
    try testing.expectEqual(2048, cfg.mmap_threshold);
}

/// handleTimezone handles the timezone option.
/// Accepts formats like: "+1", "-5", "+5:30", "-3:30"
// pub fn handleTimezone(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
//     _ = allocator;
//     if (value) |tz_str| {
//         // Parse timezone offset
//         const is_negative = tz_str[0] == '-';
//         const start_idx: usize = if (tz_str[0] == '+' or tz_str[0] == '-') 1 else 0;

//         var hours: i64 = 0;
//         var minutes: i64 = 0;

//         if (std.mem.indexOf(u8, tz_str, ":")) |colon_pos| {
//             // Format: "+5:30" or "-3:30"
//             hours = try std.fmt.parseInt(i64, tz_str[start_idx..colon_pos], 10);
//             minutes = try std.fmt.parseInt(i64, tz_str[colon_pos + 1 ..], 10);
//         } else {
//             // Format: "+1" or "-5"
//             hours = try std.fmt.parseInt(i64, tz_str[start_idx..], 10);
//         }

//         var offset_seconds = hours * 3600 + minutes * 60;
//         if (is_negative) {
//             offset_seconds = -offset_seconds;
//         }

//         cfg.timezone_offset = offset_seconds;
//     }
// }
pub fn handleTimezone(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    const tz_str = value orelse return;
    if (tz_str.len == 0) return;

    const is_negative = tz_str[0] == '-';
    const start_idx: usize = if (tz_str[0] == '+' or tz_str[0] == '-') 1 else 0;

    var hours: i64 = 0;
    var minutes: i64 = 0;

    if (std.mem.indexOf(u8, tz_str, ":")) |colon_pos| {
        hours = try std.fmt.parseInt(i64, tz_str[start_idx..colon_pos], 10);
        minutes = try std.fmt.parseInt(i64, tz_str[colon_pos + 1 ..], 10);

        // --- ADD VALIDATION HERE ---
        if (minutes < 0 or minutes > 59) return error.InvalidTimezoneMinutes;
        if (hours < 0 or hours > 14) return error.InvalidTimezoneHours;
    } else {
        hours = try std.fmt.parseInt(i64, tz_str[start_idx..], 10);
        if (hours < 0 or hours > 14) return error.InvalidTimezoneHours;
    }

    var offset_seconds = hours * 3600 + minutes * 60;
    if (is_negative) offset_seconds = -offset_seconds;

    cfg.timezone_offset = offset_seconds;
}

test "handleTimezone handles timezone option" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleTimezone(&cfg, allocator, "+5");
    try testing.expectEqual(@as(i64, 18000), cfg.timezone_offset);

    try handleTimezone(&cfg, allocator, "-3:30");
    try testing.expectEqual(@as(i64, -12600), cfg.timezone_offset);
}

test "handleTimezone handles invalid timezone option" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    // 1. We expect an error here, NOT a successful return
    const result_invalid_mins = handleTimezone(&cfg, allocator, "+5:60");
    try testing.expectError(error.InvalidTimezoneMinutes, result_invalid_mins);

    // 2. We expect an error here because "30:00" is not a valid integer
    // (std.fmt.parseInt will fail on the second ':')
    const result_invalid_format = handleTimezone(&cfg, allocator, "-3:30:00");
    try testing.expectError(error.InvalidCharacter, result_invalid_format);
}
