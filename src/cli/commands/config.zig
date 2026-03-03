const std = @import("std");
const options = @import("../options.zig").options;
const FileConf = @import("../../conf/file.zig").FileConf;
const loadFileConf = @import("../../conf/file.zig").load;

pub const VERSION = "0.12.0";

const DEFAULT_SMALL_THRESHOLD = 1 << 20; // 1 MiB
const DEFAULT_MMAP_THRESHOLD = 16 << 20; // 16 MiB

/// ConfigParseResult represents the result of parsing a configuration.
pub const ConfigParseResult = union(enum) {
    Success: Config,
    MissingValue: []const u8,
    UnknownOption: []const u8,
    Other: []const u8,
};

/// Config represents the configuration for the application.
pub const Config = struct {
    allocator: std.mem.Allocator,
    paths: std.ArrayList([]const u8),
    small_threshold: usize,
    mmap_threshold: usize,
    skip_git: bool,
    skip_cache: bool,
    ignore_patterns: []const u8,
    n_threads: usize,
    timezone_offset: ?i64, // Offset in seconds from UTC (e.g., 3600 for UTC+1)
    version: []const u8 = VERSION,
    watch: bool,
    output: ?[]u8, // Output filename; null means "report.md"
    json_output: bool, // Emit report.json alongside report.md
    html_output: bool, // Emit report.html alongside report.md

    // Internal tracking for memory management and CLI override behavior.
    // These are not user-facing; they track whether list fields were set by CLI
    // so that CLI args properly override file config values.
    _ignore_patterns_allocated: bool,
    _paths_set_by_cli: bool,
    _patterns_set_by_cli: bool,

    const Self = @This();

    /// Initializes a default configuration.
    pub fn initDefault(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .paths = .empty,
            .small_threshold = DEFAULT_SMALL_THRESHOLD, // 1 MiB
            .mmap_threshold = DEFAULT_MMAP_THRESHOLD, // 16 MiB
            .skip_git = false,
            .skip_cache = false,
            .ignore_patterns = "",
            .n_threads = std.Thread.getCpuCount() catch 1,
            .timezone_offset = null,
            .watch = false,
            .output = null,
            .json_output = false,
            .html_output = false,
            ._ignore_patterns_allocated = false,
            ._paths_set_by_cli = false,
            ._patterns_set_by_cli = false,
        };
    }

    /// Parses a timezone string like "+1", "-5", "+5:30" into a UTC offset in seconds.
    pub fn parseTimezoneStr(tz_str: []const u8) !i64 {
        if (tz_str.len == 0) return 0;

        const is_negative = tz_str[0] == '-';
        const start_idx: usize = if (tz_str[0] == '+' or tz_str[0] == '-') 1 else 0;

        var hours: i64 = 0;
        var minutes: i64 = 0;

        if (std.mem.indexOf(u8, tz_str, ":")) |colon_pos| {
            hours = try std.fmt.parseInt(i64, tz_str[start_idx..colon_pos], 10);
            minutes = try std.fmt.parseInt(i64, tz_str[colon_pos + 1 ..], 10);
            if (minutes < 0 or minutes > 59) return error.InvalidTimezoneMinutes;
            if (hours < 0 or hours > 14) return error.InvalidTimezoneHours;
        } else {
            hours = try std.fmt.parseInt(i64, tz_str[start_idx..], 10);
            if (hours < 0 or hours > 14) return error.InvalidTimezoneHours;
        }

        var offset_seconds = hours * 3600 + minutes * 60;
        if (is_negative) offset_seconds = -offset_seconds;
        return offset_seconds;
    }

    /// Appends an ignore pattern, managing memory ownership.
    pub fn appendIgnorePattern(self: *Self, allocator: std.mem.Allocator, pattern: []const u8) !void {
        if (self.ignore_patterns.len == 0) {
            self.ignore_patterns = try allocator.dupe(u8, pattern);
            self._ignore_patterns_allocated = true;
        } else {
            const new = try std.fmt.allocPrint(allocator, "{s},{s}", .{ self.ignore_patterns, pattern });
            if (self._ignore_patterns_allocated) allocator.free(self.ignore_patterns);
            self.ignore_patterns = new;
            self._ignore_patterns_allocated = true;
        }
    }

    /// Clears all ignore patterns, freeing allocated memory.
    pub fn clearIgnorePatterns(self: *Self, allocator: std.mem.Allocator) void {
        if (self._ignore_patterns_allocated) {
            allocator.free(self.ignore_patterns);
            self._ignore_patterns_allocated = false;
        }
        self.ignore_patterns = "";
    }

    /// Applies values from a FileConf to this Config.
    /// File values override defaults but CLI args will override file values later.
    pub fn applyFileConf(self: *Self, conf: *const FileConf, allocator: std.mem.Allocator) !void {
        // Apply paths
        if (conf.paths) |paths| {
            for (paths) |path| {
                const owned = try allocator.dupe(u8, path);
                try self.paths.append(allocator, owned);
            }
        }

        // Apply ignore patterns
        if (conf.ignore_patterns) |patterns| {
            for (patterns) |pattern| {
                const trimmed = std.mem.trim(u8, pattern, " \t\n\r");
                if (trimmed.len > 0) {
                    try self.appendIgnorePattern(allocator, trimmed);
                }
            }
        }

        // Apply scalar values
        if (conf.skip_cache) |v| self.skip_cache = v;
        if (conf.skip_git) |v| self.skip_git = v;
        if (conf.small_threshold) |v| self.small_threshold = v;
        if (conf.mmap_threshold) |v| self.mmap_threshold = v;
        if (conf.watch) |v| self.watch = v;

        // Apply timezone
        if (conf.timezone) |tz| {
            self.timezone_offset = try Self.parseTimezoneStr(tz);
        }

        // Apply output filename
        if (conf.output) |out| {
            if (self.output) |existing| allocator.free(existing);
            self.output = try allocator.dupe(u8, out);
        }

        // Apply json output flag
        if (conf.json_output) |v| self.json_output = v;

        // Apply html output flag
        if (conf.html_output) |v| self.html_output = v;
    }

    /// Parses CLI args only, without loading any file config.
    /// Used for direct testing and backward compatibility.
    pub fn parse(args: [][]const u8, allocator: std.mem.Allocator) ConfigParseResult {
        var cfg = Self.initDefault(allocator);
        return applyArgs(&cfg, args, allocator);
    }

    /// Loads zig.conf.json as base config, then applies CLI args on top.
    /// CLI args override file config values for the fields they touch.
    pub fn parseFromFile(args: [][]const u8, allocator: std.mem.Allocator) ConfigParseResult {
        var cfg = Self.initDefault(allocator);

        // Try to load zig.conf.json as base configuration
        const maybe_conf = loadFileConf(allocator) catch |err| blk: {
            std.log.warn("zigzag: could not read zig.conf.json: {s}", .{@errorName(err)});
            break :blk null;
        };
        if (maybe_conf) |parsed_conf| {
            var fc = parsed_conf;
            defer fc.deinit();
            cfg.applyFileConf(&fc.value, allocator) catch |err| {
                std.log.warn("zigzag: could not apply zig.conf.json: {s}", .{@errorName(err)});
            };
        }

        return applyArgs(&cfg, args, allocator);
    }

    /// Applies CLI args to an existing Config, returning a ConfigParseResult.
    fn applyArgs(cfg: *Self, args: [][]const u8, allocator: std.mem.Allocator) ConfigParseResult {
        var i: usize = 0;
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            var handled = false;

            for (options) |opt| {
                if (std.mem.eql(u8, arg, opt.name)) {
                    var value: ?[]const u8 = null;
                    if (opt.takes_value) {
                        i += 1;
                        if (i < args.len) {
                            value = args[i];
                        } else {
                            return ConfigParseResult{ .MissingValue = opt.name };
                        }
                    }

                    opt.handler(cfg, allocator, value) catch |err| {
                        const err_name = @errorName(err);
                        return ConfigParseResult{ .Other = err_name };
                    };

                    handled = true;
                    break;
                }
            }

            if (!handled) {
                return ConfigParseResult{ .UnknownOption = arg };
            }
        }

        return ConfigParseResult{ .Success = cfg.* };
    }

    pub fn deinit(self: *Self) void {
        for (self.paths.items) |path| {
            self.allocator.free(path);
        }
        self.paths.deinit(self.allocator);

        if (self._ignore_patterns_allocated) {
            self.allocator.free(self.ignore_patterns);
        }

        if (self.output) |out| {
            self.allocator.free(out);
        }
    }
};

test "Config.initDefault has expected defaults" {
    const allocator = std.testing.allocator;
    var cfg = Config.initDefault(allocator);
    defer cfg.deinit();

    try std.testing.expectEqual(@as(usize, 1 << 20), cfg.small_threshold);
    try std.testing.expectEqual(@as(usize, 16 << 20), cfg.mmap_threshold);
    try std.testing.expect(!cfg.skip_cache);
    try std.testing.expect(!cfg.skip_git);
    try std.testing.expect(!cfg.watch);
    try std.testing.expect(!cfg.json_output);
    try std.testing.expect(!cfg.html_output);
    try std.testing.expect(cfg.output == null);
    try std.testing.expect(cfg.timezone_offset == null);
    try std.testing.expectEqual(@as(usize, 0), cfg.paths.items.len);
    try std.testing.expectEqualStrings("", cfg.ignore_patterns);
}

test "Config.parseTimezoneStr parses positive offset" {
    try std.testing.expectEqual(@as(i64, 3600), try Config.parseTimezoneStr("+1"));
    try std.testing.expectEqual(@as(i64, 18000), try Config.parseTimezoneStr("+5"));
    try std.testing.expectEqual(@as(i64, 19800), try Config.parseTimezoneStr("+5:30"));
}

test "Config.parseTimezoneStr parses negative offset" {
    try std.testing.expectEqual(@as(i64, -10800), try Config.parseTimezoneStr("-3"));
    try std.testing.expectEqual(@as(i64, -12600), try Config.parseTimezoneStr("-3:30"));
}

test "Config.parseTimezoneStr parses no-sign offset" {
    try std.testing.expectEqual(@as(i64, 3600), try Config.parseTimezoneStr("1"));
}

test "Config.parseTimezoneStr returns error for invalid minutes" {
    try std.testing.expectError(error.InvalidTimezoneMinutes, Config.parseTimezoneStr("+5:60"));
}

test "Config.parseTimezoneStr returns error for invalid hours" {
    try std.testing.expectError(error.InvalidTimezoneHours, Config.parseTimezoneStr("+15"));
}

test "Config.appendIgnorePattern accumulates patterns" {
    const allocator = std.testing.allocator;
    var cfg = Config.initDefault(allocator);
    defer cfg.deinit();

    try cfg.appendIgnorePattern(allocator, "*.png");
    try std.testing.expectEqualStrings("*.png", cfg.ignore_patterns);

    try cfg.appendIgnorePattern(allocator, "*.jpg");
    try std.testing.expectEqualStrings("*.png,*.jpg", cfg.ignore_patterns);
}

test "Config.clearIgnorePatterns frees memory" {
    const allocator = std.testing.allocator;
    var cfg = Config.initDefault(allocator);
    defer cfg.deinit();

    try cfg.appendIgnorePattern(allocator, "*.png");
    cfg.clearIgnorePatterns(allocator);
    try std.testing.expectEqualStrings("", cfg.ignore_patterns);
    try std.testing.expect(!cfg._ignore_patterns_allocated);
}

test "Config.applyFileConf applies paths" {
    const allocator = std.testing.allocator;
    var cfg = Config.initDefault(allocator);
    defer cfg.deinit();

    const paths = [_][]const u8{ "./src", "./lib" };
    const conf = FileConf{ .paths = &paths };
    try cfg.applyFileConf(&conf, allocator);

    try std.testing.expectEqual(@as(usize, 2), cfg.paths.items.len);
    try std.testing.expectEqualStrings("./src", cfg.paths.items[0]);
    try std.testing.expectEqualStrings("./lib", cfg.paths.items[1]);
}

test "Config.applyFileConf applies ignore patterns" {
    const allocator = std.testing.allocator;
    var cfg = Config.initDefault(allocator);
    defer cfg.deinit();

    const patterns = [_][]const u8{ "*.png", "*.jpg" };
    const conf = FileConf{ .ignore_patterns = &patterns };
    try cfg.applyFileConf(&conf, allocator);

    try std.testing.expect(std.mem.indexOf(u8, cfg.ignore_patterns, "*.png") != null);
    try std.testing.expect(std.mem.indexOf(u8, cfg.ignore_patterns, "*.jpg") != null);
}

test "Config.applyFileConf applies scalar values" {
    const allocator = std.testing.allocator;
    var cfg = Config.initDefault(allocator);
    defer cfg.deinit();

    const conf = FileConf{
        .skip_cache = true,
        .skip_git = true,
        .watch = true,
        .small_threshold = 2048,
        .mmap_threshold = 4096,
    };
    try cfg.applyFileConf(&conf, allocator);

    try std.testing.expect(cfg.skip_cache);
    try std.testing.expect(cfg.skip_git);
    try std.testing.expect(cfg.watch);
    try std.testing.expectEqual(@as(usize, 2048), cfg.small_threshold);
    try std.testing.expectEqual(@as(usize, 4096), cfg.mmap_threshold);
}

test "Config.applyFileConf applies timezone" {
    const allocator = std.testing.allocator;
    var cfg = Config.initDefault(allocator);
    defer cfg.deinit();

    const conf = FileConf{ .timezone = "+5:30" };
    try cfg.applyFileConf(&conf, allocator);
    try std.testing.expectEqual(@as(i64, 19800), cfg.timezone_offset.?);
}

test "Config.applyFileConf applies output filename" {
    const allocator = std.testing.allocator;
    var cfg = Config.initDefault(allocator);
    defer cfg.deinit();

    const conf = FileConf{ .output = "output.md" };
    try cfg.applyFileConf(&conf, allocator);
    try std.testing.expectEqualStrings("output.md", cfg.output.?);
}

test "Config.applyFileConf applies json_output true" {
    const allocator = std.testing.allocator;
    var cfg = Config.initDefault(allocator);
    defer cfg.deinit();

    const conf = FileConf{ .json_output = true };
    try cfg.applyFileConf(&conf, allocator);
    try std.testing.expect(cfg.json_output);
}

test "Config.applyFileConf leaves json_output unchanged when FileConf field is null" {
    const allocator = std.testing.allocator;
    var cfg = Config.initDefault(allocator);
    defer cfg.deinit();

    const conf = FileConf{};
    try cfg.applyFileConf(&conf, allocator);
    try std.testing.expect(!cfg.json_output);
}

test "Config.applyFileConf applies html_output true" {
    const allocator = std.testing.allocator;
    var cfg = Config.initDefault(allocator);
    defer cfg.deinit();

    const conf = FileConf{ .html_output = true };
    try cfg.applyFileConf(&conf, allocator);
    try std.testing.expect(cfg.html_output);
}

test "Config.applyFileConf leaves html_output unchanged when FileConf field is null" {
    const allocator = std.testing.allocator;
    var cfg = Config.initDefault(allocator);
    defer cfg.deinit();

    const conf = FileConf{};
    try cfg.applyFileConf(&conf, allocator);
    try std.testing.expect(!cfg.html_output);
}

test "Config.applyFileConf is idempotent when conf is empty" {
    const allocator = std.testing.allocator;
    var cfg = Config.initDefault(allocator);
    defer cfg.deinit();

    const conf = FileConf{};
    try cfg.applyFileConf(&conf, allocator);

    try std.testing.expectEqual(@as(usize, 0), cfg.paths.items.len);
    try std.testing.expectEqualStrings("", cfg.ignore_patterns);
    try std.testing.expect(!cfg.skip_cache);
    try std.testing.expect(cfg.output == null);
}

test "Config.parse returns UnknownOption for unrecognized flag" {
    const allocator = std.testing.allocator;
    var args = [_][]const u8{"--unknown-flag"};
    const result = Config.parse(&args, allocator);
    switch (result) {
        .UnknownOption => |opt| try std.testing.expectEqualStrings("--unknown-flag", opt),
        else => return error.WrongVariant,
    }
}

test "Config.parse returns MissingValue when flag value is absent" {
    const allocator = std.testing.allocator;
    var args = [_][]const u8{"--path"};
    const result = Config.parse(&args, allocator);
    switch (result) {
        .MissingValue => |opt| try std.testing.expectEqualStrings("--path", opt),
        else => return error.WrongVariant,
    }
}

test "Config.parse handles empty args" {
    const allocator = std.testing.allocator;
    var args = [_][]const u8{};
    const result = Config.parse(&args, allocator);
    switch (result) {
        .Success => |cfg| {
            var c = cfg;
            defer c.deinit();
            try std.testing.expectEqual(@as(usize, 0), c.paths.items.len);
        },
        else => return error.WrongVariant,
    }
}
