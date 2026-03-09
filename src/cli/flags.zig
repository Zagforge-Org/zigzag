const std = @import("std");
const Config = @import("./commands/config/config.zig").Config;

const versionHandler = @import("./handlers/version.zig").printVersion;
const helpHandler = @import("./handlers/help.zig").printHelp;
const skipCacheHandler = @import("./handlers/skip_cache.zig").handleSkipCache;
const smallHandler = @import("./handlers/small.zig").handleSmall;
const mmapHandler = @import("./handlers/mmap.zig").handleMmap;
const pathHandler = @import("./handlers/path.zig").handlePath;
const ignoreHandler = @import("./handlers/ignore.zig").handleIgnore;
const timezoneHandler = @import("./handlers/timezone.zig").handleTimezone;
const watchHandler = @import("./handlers/watch.zig").handleWatch;
const outputHandler = @import("./handlers/output.zig").handleOutput;
const outputDirHandler = @import("./handlers/output_dir.zig").handleOutputDir;
const jsonHandler = @import("./handlers/json.zig").handleJson;
const htmlHandler = @import("./handlers/html.zig").handleHtml;
const llmReportHandler = @import("./handlers/llm_report.zig").handleLlmReport;
const portHandler = @import("./handlers/port.zig").handlePort;
const logHandler = @import("./handlers/log.zig").handleLog;
const openHandler = @import("./handlers/open.zig").handleOpen;

///  FlagsHandler represents a command-line flag.
pub const FlagsHandler = struct {
    name: []const u8,
    takes_value: bool,
    handler: *const fn (*Config, std.mem.Allocator, ?[]const u8) anyerror!void,
};

pub const flags = [_]FlagsHandler{
    .{ .name = "--version", .takes_value = false, .handler = &versionHandler },
    .{ .name = "--help", .takes_value = false, .handler = &helpHandler },
    .{ .name = "--skip-cache", .takes_value = false, .handler = &skipCacheHandler },
    .{ .name = "--small", .takes_value = true, .handler = &smallHandler },
    .{ .name = "--mmap", .takes_value = true, .handler = &mmapHandler },
    .{ .name = "--path", .takes_value = true, .handler = &pathHandler },
    .{ .name = "--ignore", .takes_value = true, .handler = &ignoreHandler },
    .{ .name = "--timezone", .takes_value = true, .handler = &timezoneHandler },
    .{ .name = "--watch", .takes_value = false, .handler = &watchHandler },
    .{ .name = "--output", .takes_value = true, .handler = &outputHandler },
    .{ .name = "--output-dir", .takes_value = true, .handler = &outputDirHandler },
    .{ .name = "--json", .takes_value = false, .handler = &jsonHandler },
    .{ .name = "--html", .takes_value = false, .handler = &htmlHandler },
    .{ .name = "--llm-report", .takes_value = false, .handler = &llmReportHandler },
    .{ .name = "--port", .takes_value = true, .handler = &portHandler },
    .{ .name = "--log", .takes_value = false, .handler = &logHandler },
    .{ .name = "--open", .takes_value = false, .handler = &openHandler },
};
