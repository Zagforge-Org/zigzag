const std = @import("std");
const Config = @import("./commands/config.zig").Config;
const defaultContent = @import("../conf/file.zig").defaultContent;
const DEFAULT_CONF_FILENAME = @import("../conf/file.zig").DEFAULT_CONF_FILENAME;
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
        \\version {s}
        \\
    , .{
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
        \\Usage: zigzag [COMMAND] [OPTIONS]
        \\
        \\Commands:
        \\  init            Initialize a new project (creates zig.conf.json)
        \\  run             Run using zig.conf.json (flags override config file)
        \\
        \\Options:
        \\  --help           Print this help message
        \\  --path           Path to a project directory (can be used multiple times)
        \\  --version        Print version information
        \\  --ignore         Ignore files matching the given pattern
        \\                   Supports: exact filenames, *.ext, prefix*, *suffix, directory names
        \\  --skip-git       Skip git operations
        \\  --skip-cache     Skip cache operations
        \\  --strategy       Print strategy
        \\  --small          Small threshold in bytes (default: 1 MiB)
        \\  --mmap           Mmap threshold in bytes (default: 16 MiB)
        \\  --timezone       Timezone offset from UTC (e.g., +1, -5, +5:30)
        \\  --output         Output filename (default: report.md)
        \\  --output-dir     Base directory for report output (default: zigzag-reports)
        \\  --json           Generate a JSON report alongside the markdown report
        \\  --html           Generate an HTML report alongside the markdown report
        \\  --watch          Watch for file changes and regenerate output
        \\  --llm-report     Generate a condensed LLM-optimized report (report.llm.md)
        \\
        \\Ignore Pattern Examples:
        \\  --ignore "*.png"              Ignore all PNG files
        \\  --ignore "test.txt"           Ignore specific file
        \\  --ignore "node_modules"       Ignore directory
        \\  --ignore "*.svg" --ignore "*.jpg"  Multiple patterns
        \\
        \\Auto-ignored items:
        \\  - Binary files (images, executables, archives, etc.)
        \\  - node_modules, .git, .cache, __pycache__, etc.
        \\
        \\Examples:
        \\  zigzag run
        \\  zigzag run --path ./src --ignore "*.test.zig"
        \\  zigzag run --watch
        \\  zigzag --path ./project1 --path ./project2
        \\  zigzag --path ./src --timezone +1
        \\
    , .{});
}

test "printHelp runs without error" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();
    try printHelp(&cfg, allocator, null);
}

/// handleIgnore handles the ignore option - can be called multiple times.
/// When called via CLI, the first invocation replaces any file-config patterns.
/// Subsequent CLI invocations accumulate additional patterns.
pub fn handleIgnore(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    if (value) |pattern| {
        const trimmed = std.mem.trim(u8, pattern, " \t\n\r");
        if (trimmed.len == 0) return;

        // First CLI --ignore call: replace file-loaded patterns (CLI overrides file config)
        if (!cfg._patterns_set_by_cli) {
            cfg._patterns_set_by_cli = true;
            cfg.clearIgnorePatterns(allocator);
        }

        try cfg.appendIgnorePattern(allocator, trimmed);
    }
}

test "handleIgnore handles single pattern" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleIgnore(&cfg, allocator, "*.png");
    try testing.expect(std.mem.indexOf(u8, cfg.ignore_patterns, "*.png") != null);
}

test "handleIgnore accumulates multiple patterns" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleIgnore(&cfg, allocator, "*.png");
    try handleIgnore(&cfg, allocator, "*.jpg");
    try testing.expect(std.mem.indexOf(u8, cfg.ignore_patterns, "*.png") != null);
    try testing.expect(std.mem.indexOf(u8, cfg.ignore_patterns, "*.jpg") != null);
}

test "handleIgnore trims whitespace from pattern" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleIgnore(&cfg, allocator, "  *.png  ");
    try testing.expect(std.mem.indexOf(u8, cfg.ignore_patterns, "*.png") != null);
    try testing.expect(std.mem.indexOf(u8, cfg.ignore_patterns, " ") == null);
}

test "handleIgnore ignores empty pattern" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleIgnore(&cfg, allocator, "   ");
    try testing.expectEqualStrings("", cfg.ignore_patterns);
}

test "handleIgnore CLI overrides file-loaded patterns" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    // Simulate file-loaded patterns
    try cfg.appendIgnorePattern(allocator, "*.from_file");

    // First CLI call should replace file patterns
    try handleIgnore(&cfg, allocator, "*.from_cli");
    try testing.expect(std.mem.indexOf(u8, cfg.ignore_patterns, "*.from_file") == null);
    try testing.expect(std.mem.indexOf(u8, cfg.ignore_patterns, "*.from_cli") != null);

    // Second CLI call accumulates
    try handleIgnore(&cfg, allocator, "*.also_cli");
    try testing.expect(std.mem.indexOf(u8, cfg.ignore_patterns, "*.from_cli") != null);
    try testing.expect(std.mem.indexOf(u8, cfg.ignore_patterns, "*.also_cli") != null);
}

/// handlePath handles the path option (can be called multiple times).
/// When called via CLI, the first invocation replaces any file-config paths.
pub fn handlePath(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    if (value) |path| {
        // First CLI --path call: replace file-loaded paths (CLI overrides file config)
        if (!cfg._paths_set_by_cli) {
            cfg._paths_set_by_cli = true;
            for (cfg.paths.items) |p| allocator.free(p);
            cfg.paths.clearRetainingCapacity();
        }

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

test "handlePath accumulates multiple paths" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handlePath(&cfg, allocator, "./src");
    try handlePath(&cfg, allocator, "./lib");
    try testing.expectEqual(@as(usize, 2), cfg.paths.items.len);
    try testing.expectEqualStrings("./src", cfg.paths.items[0]);
    try testing.expectEqualStrings("./lib", cfg.paths.items[1]);
}

test "handlePath CLI overrides file-loaded paths" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    // Simulate file-loaded path
    const file_path = try allocator.dupe(u8, "./from_file");
    try cfg.paths.append(allocator, file_path);

    // First CLI --path should replace file paths
    try handlePath(&cfg, allocator, "./from_cli");
    try testing.expectEqual(@as(usize, 1), cfg.paths.items.len);
    try testing.expectEqualStrings("./from_cli", cfg.paths.items[0]);

    // Second CLI --path accumulates
    try handlePath(&cfg, allocator, "./also_cli");
    try testing.expectEqual(@as(usize, 2), cfg.paths.items.len);
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
pub fn handleTimezone(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    const tz_str = value orelse return;
    if (tz_str.len == 0) return;
    cfg.timezone_offset = try Config.parseTimezoneStr(tz_str);
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

    const result_invalid_mins = handleTimezone(&cfg, allocator, "+5:60");
    try testing.expectError(error.InvalidTimezoneMinutes, result_invalid_mins);

    const result_invalid_format = handleTimezone(&cfg, allocator, "-3:30:00");
    try testing.expectError(error.InvalidCharacter, result_invalid_format);
}

/// handleWatch enables watch mode.
pub fn handleWatch(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    cfg.watch = true;
}

test "handleWatch enables watch mode" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try testing.expect(!cfg.watch);
    try handleWatch(&cfg, allocator, null);
    try testing.expect(cfg.watch);
}

/// handleOutput sets the output filename for the generated report.
pub fn handleOutput(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    if (value) |filename| {
        const trimmed = std.mem.trim(u8, filename, " \t\n\r");
        if (trimmed.len == 0) return;

        if (cfg.output) |existing| allocator.free(existing);
        cfg.output = try allocator.dupe(u8, trimmed);
    }
}

test "handleOutput sets output filename" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleOutput(&cfg, allocator, "custom.md");
    try testing.expectEqualStrings("custom.md", cfg.output.?);
}

test "handleOutput trims whitespace" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleOutput(&cfg, allocator, "  output.md  ");
    try testing.expectEqualStrings("output.md", cfg.output.?);
}

test "handleOutput ignores empty filename" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleOutput(&cfg, allocator, "   ");
    try testing.expect(cfg.output == null);
}

test "handleOutput replaces previous output value" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleOutput(&cfg, allocator, "first.md");
    try handleOutput(&cfg, allocator, "second.md");
    try testing.expectEqualStrings("second.md", cfg.output.?);
}

/// handleOutputDir sets the base output directory for generated reports.
pub fn handleOutputDir(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    if (value) |v| {
        const trimmed = std.mem.trim(u8, v, " \t\r\n");
        if (trimmed.len == 0) return;
        if (cfg._output_dir_allocated) {
            if (cfg.output_dir) |existing| allocator.free(existing);
        }
        cfg.output_dir = try allocator.dupe(u8, trimmed);
        cfg._output_dir_allocated = true;
        cfg._output_dir_set_by_cli = true;
    }
}

test "handleOutputDir sets output_dir" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleOutputDir(&cfg, allocator, "my-reports");
    try testing.expectEqualStrings("my-reports", cfg.output_dir.?);
    try testing.expect(cfg._output_dir_set_by_cli);
}

test "handleOutputDir trims whitespace" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleOutputDir(&cfg, allocator, "  reports/  ");
    try testing.expectEqualStrings("reports/", cfg.output_dir.?);
}

test "handleOutputDir replaces previous value" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleOutputDir(&cfg, allocator, "first");
    try handleOutputDir(&cfg, allocator, "second");
    try testing.expectEqualStrings("second", cfg.output_dir.?);
}

test "handleOutputDir ignores empty value" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleOutputDir(&cfg, allocator, "   ");
    try testing.expect(cfg.output_dir == null);
    try testing.expect(!cfg._output_dir_set_by_cli);
}

/// handleJson enables JSON report output alongside the markdown report.
pub fn handleJson(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    cfg.json_output = true;
}

test "handleJson sets json_output to true" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();
    try std.testing.expect(!cfg.json_output);
    try handleJson(&cfg, allocator, null);
    try std.testing.expect(cfg.json_output);
}

/// handleHtml enables HTML report output alongside the markdown report.
pub fn handleHtml(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    cfg.html_output = true;
}

test "handleHtml sets html_output to true" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();
    try std.testing.expect(!cfg.html_output);
    try handleHtml(&cfg, allocator, null);
    try std.testing.expect(cfg.html_output);
}

/// handleLlmReport enables LLM-optimized report output alongside the markdown report.
pub fn handleLlmReport(cfg: *Config, allocator: std.mem.Allocator, _: ?[]const u8) anyerror!void {
    _ = allocator;
    cfg.llm_report = true;
}

test "handleLlmReport sets llm_report to true" {
    var cfg = Config.initDefault(std.testing.allocator);
    defer cfg.deinit();
    try handleLlmReport(&cfg, std.testing.allocator, null);
    try std.testing.expect(cfg.llm_report);
}

/// handleInit creates the zig.conf.json configuration file with default values.
/// dir is the directory in which to create the file (use std.fs.cwd() for normal use).
pub fn handleInit(allocator: std.mem.Allocator, dir: std.fs.Dir) anyerror!void {
    _ = allocator;

    const file = dir.createFile(DEFAULT_CONF_FILENAME, .{
        .read = true,
        .exclusive = true,
    }) catch |err| switch (err) {
        error.PathAlreadyExists => {
            std.log.info("zigzag: {s} already exists", .{DEFAULT_CONF_FILENAME});
            return;
        },
        else => return err,
    };
    defer file.close();

    try file.writeAll(defaultContent());
    std.log.info("zigzag: created {s}", .{DEFAULT_CONF_FILENAME});
}

test "handleInit creates file with default content" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try handleInit(allocator, tmp_dir.dir);

    // Verify file was created with valid default JSON
    const content = try tmp_dir.dir.readFileAlloc(allocator, DEFAULT_CONF_FILENAME, 1 << 20);
    defer allocator.free(content);

    try testing.expect(content.len > 0);

    const parsed = try std.json.parseFromSlice(
        @import("../conf/file.zig").FileConf,
        allocator,
        content,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    try testing.expect(parsed.value.watch.? == false);
    try testing.expectEqualStrings("report.md", parsed.value.output.?);
}

test "handleInit does not overwrite existing file" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create the file with custom content first
    {
        const f = try tmp_dir.dir.createFile(DEFAULT_CONF_FILENAME, .{});
        defer f.close();
        try f.writeAll("{\"watch\": true}");
    }

    // handleInit should not overwrite
    try handleInit(allocator, tmp_dir.dir);

    const content = try tmp_dir.dir.readFileAlloc(allocator, DEFAULT_CONF_FILENAME, 1 << 20);
    defer allocator.free(content);

    try testing.expectEqualStrings("{\"watch\": true}", content);
}
