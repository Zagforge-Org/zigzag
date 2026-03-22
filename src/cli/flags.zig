const std = @import("std");
const Config = @import("./commands/config/config.zig").Config;

const versionHandler = @import("./handlers/display/version.zig").printVersion;
const helpHandler = @import("./handlers/display/help.zig").printHelp;
const skipCacheHandler = @import("./handlers/flags/skip_cache.zig").handleSkipCache;
const smallHandler = @import("./handlers/flags/small.zig").handleSmall;
const mmapHandler = @import("./handlers/flags/mmap.zig").handleMmap;
const pathHandler = @import("./handlers/flags/path.zig").handlePaths;
const ignoreHandler = @import("./handlers/flags/ignore.zig").handleIgnores;
const timezoneHandler = @import("./handlers/flags/timezone.zig").handleTimezone;
const watchHandler = @import("./handlers/flags/watch.zig").handleWatch;
const noWatchHandler = @import("./handlers/flags/no_watch.zig").handleNoWatch;
const outputHandler = @import("./handlers/flags/output.zig").handleOutput;
const outputDirHandler = @import("./handlers/flags/output_dir.zig").handleOutputDir;
const jsonHandler = @import("./handlers/flags/json.zig").handleJson;
const htmlHandler = @import("./handlers/flags/html.zig").handleHtml;
const llmReportHandler = @import("./handlers/flags/llm_report.zig").handleLlmReport;
const chunkSizeHandler = @import("./handlers/flags/chunk_size.zig").handleChunkSize;
const portHandler = @import("./handlers/flags/port.zig").handlePort;
const logHandler = @import("./handlers/flags/log.zig").handleLog;
const openHandler = @import("./handlers/flags/open.zig").handleOpen;
const uploadHandler = @import("./handlers/flags/upload.zig").handleUpload;

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
    .{ .name = "--paths", .takes_value = true, .handler = &pathHandler },
    .{ .name = "--ignores", .takes_value = true, .handler = &ignoreHandler },
    .{ .name = "--timezone", .takes_value = true, .handler = &timezoneHandler },
    .{ .name = "--watch", .takes_value = false, .handler = &watchHandler },
    .{ .name = "--no-watch", .takes_value = false, .handler = &noWatchHandler },
    .{ .name = "--output", .takes_value = true, .handler = &outputHandler },
    .{ .name = "--output-dir", .takes_value = true, .handler = &outputDirHandler },
    .{ .name = "--json", .takes_value = false, .handler = &jsonHandler },
    .{ .name = "--html", .takes_value = false, .handler = &htmlHandler },
    .{ .name = "--llm-report", .takes_value = false, .handler = &llmReportHandler },
    .{ .name = "--chunk-size", .takes_value = true, .handler = &chunkSizeHandler },
    .{ .name = "--port", .takes_value = true, .handler = &portHandler },
    .{ .name = "--log", .takes_value = false, .handler = &logHandler },
    .{ .name = "--open", .takes_value = false, .handler = &openHandler },
    .{ .name = "--upload", .takes_value = false, .handler = &uploadHandler },
};
