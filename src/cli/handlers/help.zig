const std = @import("std");
const Config = @import("../commands/config.zig").Config;
const stdoutPrint = @import("../../fs/stdout.zig").stdoutPrint;
const makeTestConfig = @import("./test_config.zig").makeTestConfig;

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
