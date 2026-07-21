//! Config is the resolved configuration for the zigzag tool, built from defaults,
//! an optional zig.conf.json, and CLI flags (CLI overrides file config).

const std = @import("std");
const flags = @import("../../flags.zig").flags;
const FileConf = @import("../../../conf/FileConf.zig");
const parseTimezoneStr = @import("./timezone.zig").parseTimezoneStr;

pub const VERSION = @import("options").version_string;

const DEFAULT_SMALL_THRESHOLD = 1 << 20; // 1 MiB
const DEFAULT_MMAP_THRESHOLD = 16 << 20; // 16 MiB
const DEFAULT_LLM_MAX_LINES = 150;
const DEFAULT_SERVE_PORT = 5455;

const Self = @This();

/// The outcome of parsing configuration from CLI args.
pub const ConfigParseResult = union(enum) {
    Success: Self,
    MissingValue: []const u8,
    UnknownOption: []const u8,
    Other: []const u8,
};

allocator: std.mem.Allocator,
paths: std.ArrayList([]const u8) = .empty,
small_threshold: usize = DEFAULT_SMALL_THRESHOLD,
mmap_threshold: usize = DEFAULT_MMAP_THRESHOLD,
skip_cache: bool = false,
ignore_patterns: std.ArrayList([]const u8) = .empty,
n_threads: usize = 1,
timezone_offset: ?i64 = null, // Offset in seconds from UTC (e.g. 3600 for UTC+1)
version: []const u8 = VERSION,
watch: bool = false,
log: bool = false,
output: ?[]u8 = null, // Output filename; null means "report.md"
json_output: bool = false, // Emit report.json alongside report.md
html_output: bool = false, // Emit report.html alongside report.md
output_dir: ?[]u8 = null, // Base output directory; null means "zigzag-reports"
llm_report: bool = false, // Generate LLM-optimized condensed report
llm_max_lines: u64 = DEFAULT_LLM_MAX_LINES, // Max lines per file before truncation
llm_description: ?[]u8 = null, // Optional project description for LLM report preamble
llm_chunk_size: usize = 0, // Max lines per chunk for LLM report (0 = no chunking)
serve_port: u16 = DEFAULT_SERVE_PORT, // Port for SSE/HTML dev server in watch+html mode
open_browser: bool = false, // Open browser automatically on serve/watch
llm_signatures: bool = false, // Emit declaration signatures + line ranges instead of condensed bodies

// Internal tracking (not user-facing): records whether a field was set by CLI so
// that CLI args override file-config values, and whether owned strings need freeing.
_paths_set_by_cli: bool = false,
_patterns_set_by_cli: bool = false,
_output_dir_allocated: bool = false,
_output_dir_set_by_cli: bool = false,
_llm_description_allocated: bool = false,
_no_watch_set_by_cli: bool = false,

/// Returns a Config populated with defaults.
pub fn default(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,
        .n_threads = std.Thread.getCpuCount() catch 1,
    };
}

pub fn deinit(self: *Self) void {
    for (self.paths.items) |path| self.allocator.free(path);
    self.paths.deinit(self.allocator);

    for (self.ignore_patterns.items) |pattern| self.allocator.free(pattern);
    self.ignore_patterns.deinit(self.allocator);

    if (self.output) |out| self.allocator.free(out);
    if (self._output_dir_allocated) {
        if (self.output_dir) |dir| self.allocator.free(dir);
    }
    if (self._llm_description_allocated) {
        if (self.llm_description) |desc| self.allocator.free(desc);
    }
}

/// Appends an ignore pattern (trimmed, non-empty), taking ownership of a copy.
pub fn appendIgnorePattern(self: *Self, pattern: []const u8) !void {
    const trimmed = std.mem.trim(u8, pattern, &std.ascii.whitespace);
    if (trimmed.len == 0) return;

    const owned = try self.allocator.dupe(u8, trimmed);
    errdefer self.allocator.free(owned);
    try self.ignore_patterns.append(self.allocator, owned);
}

/// Clears all ignore patterns, freeing the owned memory.
pub fn clearIgnorePatterns(self: *Self) void {
    for (self.ignore_patterns.items) |pattern| self.allocator.free(pattern);
    self.ignore_patterns.clearRetainingCapacity();
}

/// Applies configuration loaded from zig.conf.json. CLI-set fields are preserved.
pub fn applyFileConf(self: *Self, conf: *const FileConf) !void {
    if (conf.paths) |paths| {
        for (paths) |path| {
            const owned = try self.allocator.dupe(u8, path);
            errdefer self.allocator.free(owned);
            try self.paths.append(self.allocator, owned);
        }
    }

    if (conf.ignores) |patterns| {
        for (patterns) |pattern| try self.appendIgnorePattern(pattern);
    }

    if (conf.skip_cache) |v| self.skip_cache = v;
    if (conf.small_threshold) |v| self.small_threshold = v;
    if (conf.mmap_threshold) |v| self.mmap_threshold = v;
    if (conf.watch) |v| {
        if (!self._no_watch_set_by_cli) self.watch = v;
    }
    if (conf.log) |v| self.log = v;
    if (conf.timezone) |tz| self.timezone_offset = try parseTimezoneStr(tz);
    if (conf.json_output) |v| self.json_output = v;
    if (conf.html_output) |v| self.html_output = v;
    if (conf.llm_report) |v| self.llm_report = v;
    if (conf.llm_signatures) |v| self.llm_signatures = v;
    if (conf.llm_max_lines) |v| self.llm_max_lines = v;

    if (conf.output) |out| {
        const new_out = try self.allocator.dupe(u8, out);
        if (self.output) |old| self.allocator.free(old);
        self.output = new_out;
    }

    if (conf.output_dir) |dir| {
        if (!self._output_dir_set_by_cli)
            try self.setOwned(&self.output_dir, &self._output_dir_allocated, dir);
    }

    if (conf.llm_description) |desc|
        try self.setOwned(&self.llm_description, &self._llm_description_allocated, desc);

    if (conf.llm_chunk_size) |v| {
        const chunk: usize = switch (v) {
            .integer => |n| if (n > 0) @intCast(n) else 0,
            .float => |f| blk: {
                const n: i64 = @intFromFloat(f);
                break :blk if (n > 0) @intCast(n) else 0;
            },
            .string => |s| try parseChunkSizeStr(s),
            else => 0,
        };
        if (chunk > 0) self.llm_chunk_size = chunk;
    }
}

/// Replaces an owned optional-string field, freeing the previous value if owned.
fn setOwned(self: *Self, field: *?[]u8, allocated: *bool, value: []const u8) !void {
    const owned = try self.allocator.dupe(u8, value);
    if (allocated.*) {
        if (field.*) |old| self.allocator.free(old);
    }
    field.* = owned;
    allocated.* = true;
}

/// Parses a chunk-size string with an optional K/M suffix ("500k", "2m", "500000").
fn parseChunkSizeStr(raw: []const u8) !usize {
    const trimmed = std.mem.trim(u8, raw, &std.ascii.whitespace);
    if (trimmed.len == 0) return error.InvalidChunkSize;

    const multiplier: usize, const numeric: []const u8 = switch (trimmed[trimmed.len - 1]) {
        'k', 'K' => .{ 1_000, trimmed[0 .. trimmed.len - 1] },
        'm', 'M' => .{ 1_000_000, trimmed[0 .. trimmed.len - 1] },
        '0'...'9' => .{ 1, trimmed },
        else => return error.InvalidChunkSize,
    };

    const n = std.fmt.parseInt(usize, numeric, 10) catch return error.InvalidChunkSize;
    if (n == 0) return error.InvalidChunkSize;
    return std.math.mul(usize, n, multiplier) catch error.InvalidChunkSize;
}

/// Parses CLI args into `self`, returning the first error encountered or Success.
pub fn parse(io: std.Io, args: [][]const u8, allocator: std.mem.Allocator) ConfigParseResult {
    var cfg = default(allocator);
    return finish(&cfg, applyArgs(io, &cfg, args, allocator));
}

/// Loads zig.conf.json (best-effort) and then applies CLI args on top.
pub fn parseFromFile(io: std.Io, args: [][]const u8, allocator: std.mem.Allocator) ConfigParseResult {
    var cfg = default(allocator);
    cfg.loadFileConf(io, allocator);
    return finish(&cfg, applyArgs(io, &cfg, args, allocator));
}

/// Deinits `cfg` on any parse error; otherwise hands ownership to the result.
fn finish(cfg: *Self, result: ConfigParseResult) ConfigParseResult {
    switch (result) {
        .Success => {},
        else => cfg.deinit(),
    }
    return result;
}

/// Best-effort load of zig.conf.json into `self`; logs and continues on error.
fn loadFileConf(self: *Self, io: std.Io, allocator: std.mem.Allocator) void {
    const parsed = (FileConf.load(io, allocator) catch |err| {
        std.log.warn("zigzag: could not read zig.conf.json: {s}", .{@errorName(err)});
        return;
    }) orelse return;

    var fc = parsed;
    defer fc.deinit();
    self.applyFileConf(&fc.value) catch |err|
        std.log.warn("zigzag: could not apply zig.conf.json: {s}", .{@errorName(err)});
}

fn applyArgs(io: std.Io, self: *Self, args: [][]const u8, allocator: std.mem.Allocator) ConfigParseResult {
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        const flag = findFlag(arg) orelse return .{ .UnknownOption = arg };

        var value: ?[]const u8 = null;
        if (flag.takes_value) {
            i += 1;
            if (i >= args.len) return .{ .MissingValue = flag.name };
            value = args[i];
        }

        flag.handler(io, self, allocator, value) catch |err|
            return .{ .Other = @errorName(err) };
    }
    return .{ .Success = self.* };
}

fn findFlag(name: []const u8) ?@TypeOf(flags[0]) {
    for (flags) |flag| {
        if (std.mem.eql(u8, name, flag.name)) return flag;
    }
    return null;
}
