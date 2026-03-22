const std = @import("std");
const Config = @import("../../commands/config/config.zig").Config;
const stdoutPrint = @import("../../../fs/stdout.zig").stdoutPrint;

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
        \\  bench           Run with per-phase timing instrumentation
        \\
        \\Options:
        \\  --help           Print this help message
        \\  --paths          One or more paths, comma-separated (e.g. --paths ./src,./lib)
        \\  --version        Print version information
        \\  --ignores        One or more ignore patterns, comma-separated (e.g. --ignores "*.png,*.jpg")
        \\                   Note: paths/patterns containing a comma must be set in zig.conf.json
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
        \\  --chunk-size <N> Split LLM report into chunks of N bytes (e.g. 500k, 2m)
        \\
        \\Ignore Pattern Examples:
        \\  --ignores "*.png"             Ignore all PNG files
        \\  --ignores "test.txt"          Ignore specific file
        \\  --ignores "node_modules"      Ignore directory
        \\  --ignores "*.svg,*.jpg"       Multiple patterns
        \\
        \\Auto-ignored items:
        \\  - Binary files (images, executables, archives, etc.)
        \\  - node_modules, .git, .cache, __pycache__, etc.
        \\
        \\Examples:
        \\  zigzag run
        \\  zigzag run --paths ./src --ignores "*.test.zig"
        \\  zigzag run --watch
        \\  zigzag --paths ./project1,./project2
        \\  zigzag --paths ./src --timezone +1
        \\
    , .{});
}
