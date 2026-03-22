const std = @import("std");
const flags = @import("../../flags.zig").flags;
const FileConf = @import("../../../conf/file.zig").FileConf;
const parseTimezoneStr = @import("./timezone/timezone.zig").parseTimezoneStr;

pub const VERSION = @import("options").version_string;
const DEFAULT_SMALL_THRESHOLD = 1 << 20; // 1 MiB
const DEFAULT_MMAP_THRESHOLD = 16 << 20; // 16 MiB

/// ConfigParseResult represents the result of parsing a configuration.
pub const ConfigParseResult = union(enum) {
    Success: Config,
    MissingValue: []const u8,
    UnknownOption: []const u8,
    Other: []const u8,
};

// Config represents the configuration for the zigzag tool.
pub const Config = struct {
    allocator: std.mem.Allocator,
    paths: std.ArrayList([]const u8),
    small_threshold: usize,
    mmap_threshold: usize,
    skip_cache: bool,
    ignore_patterns: std.ArrayList([]const u8),
    n_threads: usize,
    timezone_offset: ?i64, // Offset in seconds from UTC (e.g., 3600 for UTC+1)
    version: []const u8 = VERSION,
    watch: bool,
    upload: bool,
    log: bool,
    output: ?[]u8, // Output filename; null means "report.md"
    json_output: bool, // Emit report.json alongside report.md
    html_output: bool, // Emit report.html alongside report.md
    output_dir: ?[]u8, // Base output directory; null means "zigzag-reports"
    llm_report: bool, // Generate LLM-optimized condensed report
    llm_max_lines: u64, // Max lines per file before truncation (default: 150)
    llm_description: ?[]u8, // Optional project description for LLM report preamble
    llm_chunk_size: usize, // Max lines per chunk for LLM report (0 = no chunking)
    serve_port: u16, // Port for SSE/HTML dev server in watch+html mode (default: 5455)
    open_browser: bool, // Open browser automatically on serve/watch (default: false)

    // Internal tracking for memory management and CLI override behavior.
    // These are not user-facing; they track whether list fields were set by CLI
    // so that CLI args properly override file config values.
    _ignore_patterns_allocated: bool,
    _paths_set_by_cli: bool,
    _patterns_set_by_cli: bool,
    _output_dir_allocated: bool, // true when output_dir is heap-allocated
    _output_dir_set_by_cli: bool, // true when CLI set it (prevents file conf override)
    _llm_description_allocated: bool,
    _no_watch_set_by_cli: bool, // true when --no-watch was explicitly passed

    const Self = @This();

    /// default returns a Config with default values.
    pub fn default(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .paths = .empty,
            .small_threshold = DEFAULT_SMALL_THRESHOLD, // 1 MiB
            .mmap_threshold = DEFAULT_MMAP_THRESHOLD, // 16 MiB
            .skip_cache = false,
            .ignore_patterns = .empty,
            .n_threads = std.Thread.getCpuCount() catch 1,
            .timezone_offset = null,
            .watch = false,
            .upload = false,
            .log = false,
            .output = null,
            .json_output = false,
            .html_output = false,
            ._ignore_patterns_allocated = false,
            ._paths_set_by_cli = false,
            ._patterns_set_by_cli = false,
            .output_dir = null,
            ._output_dir_allocated = false,
            ._output_dir_set_by_cli = false,
            .llm_report = false,
            .llm_max_lines = 150,
            .llm_description = null,
            ._llm_description_allocated = false,
            .llm_chunk_size = 0,
            .serve_port = 5455,
            .open_browser = false,
            ._no_watch_set_by_cli = false,
        };
    }

    // Parses a chunk size string with optional K/M suffix (e.g. "500k", "2m", "500000").
    fn parseChunkSizeStr(raw: []const u8) !usize {
        const trimmed = std.mem.trim(u8, raw, &std.ascii.whitespace);
        if (trimmed.len == 0) return error.InvalidChunkSize;
        var multiplier: usize = 1;
        var numeric: []const u8 = trimmed;
        const last = trimmed[trimmed.len - 1];
        if (last == 'k' or last == 'K') {
            multiplier = 1_000;
            numeric = trimmed[0 .. trimmed.len - 1];
        } else if (last == 'm' or last == 'M') {
            multiplier = 1_000_000;
            numeric = trimmed[0 .. trimmed.len - 1];
        } else if (last >= '0' and last <= '9') {
            // bare integer
        } else {
            return error.InvalidChunkSize;
        }
        const n = std.fmt.parseInt(usize, numeric, 10) catch return error.InvalidChunkSize;
        if (n == 0) return error.InvalidChunkSize;
        return std.math.mul(usize, n, multiplier) catch return error.InvalidChunkSize;
    }

    // Appends an ignore pattern, managing memory ownership.
    pub fn appendIgnorePattern(self: *Self, pattern: []const u8) !void {
        // Ignore empty or whitespace-only patterns.
        const trimmed = std.mem.trim(u8, pattern, &std.ascii.whitespace);
        if (trimmed.len == 0) return;

        const owned_pattern = try self.allocator.dupe(u8, trimmed);
        errdefer self.allocator.free(owned_pattern);
        try self.ignore_patterns.append(self.allocator, owned_pattern);
    }

    // Clears all ignore patterns, freeing any owned memory.
    pub fn clearIgnorePatterns(self: *Self) void {
        for (self.ignore_patterns.items) |pattern| {
            self.allocator.free(pattern);
        }
        self.ignore_patterns.clearRetainingCapacity();
    }

    // Applies configuration from a file, managing memory ownership.
    pub fn applyFileConf(self: *Self, conf: *const FileConf) !void {
        // Paths
        if (conf.paths) |paths| {
            for (paths) |path| {
                const owned = try self.allocator.dupe(u8, path);
                errdefer self.allocator.free(owned);
                try self.paths.append(self.allocator, owned);
            }
        }

        // Ignore patterns
        if (conf.ignores) |patterns| {
            for (patterns) |pattern| {
                try self.appendIgnorePattern(pattern);
            }
        }

        // Scalar flags
        if (conf.skip_cache) |v| self.skip_cache = v;
        if (conf.small_threshold) |v| self.small_threshold = v;
        if (conf.mmap_threshold) |v| self.mmap_threshold = v;
        if (!self._no_watch_set_by_cli) {
            if (conf.watch) |v| self.watch = v;
        }
        if (conf.log) |v| self.log = v;

        // Timezone
        if (conf.timezone) |tz| {
            self.timezone_offset = try parseTimezoneStr(tz);
        }

        // Output
        if (conf.output) |out| {
            const new_out = try self.allocator.dupe(u8, out);
            if (self.output) |old| self.allocator.free(old);
            self.output = new_out;
        }

        // Json output flag
        if (conf.json_output) |v| self.json_output = v;

        // Html output flag
        if (conf.html_output) |v| self.html_output = v;

        if (!self._output_dir_set_by_cli) {
            if (conf.output_dir) |dir| {
                const new_dir = try self.allocator.dupe(u8, dir);
                if (self._output_dir_allocated) {
                    if (self.output_dir) |old| self.allocator.free(old);
                }
                self.output_dir = new_dir;
                self._output_dir_allocated = true;
            }
        }

        // Upload
        if (conf.upload) |v| self.upload = v;

        // LLM report
        if (conf.llm_report) |v| self.llm_report = v;
        if (conf.llm_max_lines) |v| self.llm_max_lines = v;
        if (conf.llm_chunk_size) |v| {
            switch (v) {
                .integer => |n| {
                    if (n > 0) self.llm_chunk_size = @intCast(n);
                },
                .float => |f| {
                    const n: i64 = @intFromFloat(f);
                    if (n > 0) self.llm_chunk_size = @intCast(n);
                },
                .string => |s| {
                    self.llm_chunk_size = try parseChunkSizeStr(s);
                },
                else => {},
            }
        }

        if (conf.llm_description) |desc| {
            const new_desc = try self.allocator.dupe(u8, desc);
            if (self._llm_description_allocated) {
                if (self.llm_description) |old| self.allocator.free(old);
            }
            self.llm_description = new_desc;
            self._llm_description_allocated = true;
        }
    }

    fn applyArgs(self: *Self, args: [][]const u8, allocator: std.mem.Allocator) ConfigParseResult {
        var i: usize = 0;

        while (i < args.len) : (i += 1) {
            const arg = args[i];

            var handled = false;
            for (flags) |flag| {
                if (std.mem.eql(u8, arg, flag.name)) {
                    var value: ?[]const u8 = null;

                    if (flag.takes_value) {
                        if (i + 1 < args.len) {
                            i += 1;
                            value = args[i];
                        } else {
                            return .{ .MissingValue = flag.name };
                        }
                    }

                    flag.handler(self, allocator, value) catch |err| {
                        return .{ .Other = @errorName(err) };
                    };

                    handled = true;
                    break;
                }
            }

            if (!handled) {
                return .{ .UnknownOption = arg };
            }
        }

        return .{ .Success = self.* };
    }

    // Parses command-line arguments into a Config instance.
    pub fn parse(args: [][]const u8, allocator: std.mem.Allocator) ConfigParseResult {
        var cfg = Self.default(allocator);
        const result = applyArgs(&cfg, args, allocator);
        switch (result) {
            .Success => return .{ .Success = cfg },
            else => |err_payload| {
                cfg.deinit();
                return err_payload;
            },
        }
    }

    pub fn parseFromFile(args: [][]const u8, allocator: std.mem.Allocator) ConfigParseResult {
        var cfg = Self.default(allocator);

        // Try to load zig.conf.json
        if (FileConf.load(allocator)) |maybe_conf| {
            if (maybe_conf) |parsed_conf| {
                var fc = parsed_conf;
                defer fc.deinit();

                cfg.applyFileConf(&fc.value) catch |err| {
                    std.log.warn("zigzag: could not apply zig.conf.json: {s}", .{@errorName(err)});
                };
            }
        } else |err| {
            // Only log if it's not a "file not found" error (optional)
            std.log.warn("zigzag: could not read zig.conf.json: {s}", .{@errorName(err)});
        }

        // Capture the result of applyArgs
        const result = applyArgs(&cfg, args, allocator);

        switch (result) {
            .Success => return .{ .Success = cfg },
            else => |err_payload| {
                cfg.deinit();
                return err_payload;
            },
        }
    }
    pub fn deinit(self: *Self) void {
        for (self.paths.items) |path| {
            self.allocator.free(path);
        }
        self.paths.deinit(self.allocator);

        for (self.ignore_patterns.items) |pattern| {
            self.allocator.free(pattern);
        }
        self.ignore_patterns.deinit(self.allocator);

        if (self.output) |out| {
            self.allocator.free(out);
            self.output = null;
        }

        if (self._output_dir_allocated) {
            if (self.output_dir) |dir| {
                self.allocator.free(dir);
                self.output_dir = null;
            }
            self._output_dir_allocated = false;
        }

        if (self._llm_description_allocated) {
            if (self.llm_description) |desc| {
                self.allocator.free(desc);
                self.llm_description = null;
            }
            self._llm_description_allocated = false;
        }
    }
};
