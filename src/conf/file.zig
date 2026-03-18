const std = @import("std");

pub const DEFAULT_CONF_FILENAME = "zig.conf.json";

const END_ALLOC_SIZE = 1 << 20; // 1 MiB

/// FileConf represents structure of zig.conf.json.
/// All fields are optional - missing fields fallback to Config defaults.
pub const FileConf = struct {
    paths: ?[]const []const u8 = null,
    ignores: ?[]const []const u8 = null,
    skip_cache: ?bool = null,
    small_threshold: ?usize = null,
    mmap_threshold: ?usize = null,
    timezone: ?[]const u8 = null,
    output: ?[]const u8 = null,
    watch: ?bool = null,
    log: ?bool = null,
    json_output: ?bool = null,
    html_output: ?bool = null,
    output_dir: ?[]const u8 = null,
    llm_report: ?bool = null,
    llm_max_lines: ?u64 = null,
    llm_description: ?[]const u8 = null,
    llm_chunk_size: ?std.json.Value = null,

    /// Returns the default zig.conf.json content as a static string.
    pub fn default() []const u8 {
        return 
        \\{
        \\  "paths": [],
        \\  "ignores": [],
        \\  "skip_cache": false,
        \\  "small_threshold": 1048576,
        \\  "mmap_threshold": 16777216,
        \\  "timezone": null,
        \\  "output": "report.md",
        \\  "watch": false,
        \\  "log": false,
        \\  "json_output": false,
        \\  "html_output": false,
        \\  "output_dir": "zigzag-reports",
        \\  "llm_report": false,
        \\  "llm_max_lines": 150,
        \\  "llm_description": null,
        \\  "llm_chunk_size": null
        \\}
        \\
        ;
    }

    pub fn writeDefaultConfig(full_path: []const u8) !void {
        var buf: [1024]u8 = undefined;
        var file = try std.fs.cwd().createFile(full_path, .{});
        defer file.close();

        var w = file.writer(&buf);
        try w.interface.writeAll(FileConf.default());
        try w.interface.flush();
    }

    /// Loads and parses zigzag.conf.json from the current directory.
    /// Returns null if the file does not exist or is empty.
    /// If the file exists but is empty, create a default configuration and return it.
    pub fn load(allocator: std.mem.Allocator) !?std.json.Parsed(FileConf) {
        return try loadFromPath(allocator, DEFAULT_CONF_FILENAME);
    }

    pub fn read(allocator: std.mem.Allocator, path: []const u8) !?[]const u8 {
        const data = std.fs.cwd().readFileAlloc(allocator, path, END_ALLOC_SIZE) catch |err| {
            switch (err) {
                error.FileNotFound => return null,
                else => return err,
            }
        };

        return data;
    }

    /// loadFromPathEmpty loads a FileConf from a JSON file at the given path.
    /// Returns null if the file does not exist or is empty.
    pub fn loadFromPathEmpty(allocator: std.mem.Allocator, path: []const u8) !?std.json.Parsed(FileConf) {
        const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
            error.FileNotFound => return null,
            else => return err,
        };

        defer file.close();

        const content = try file.readToEndAlloc(allocator, END_ALLOC_SIZE);
        defer allocator.free(content);

        const slice = if (std.mem.indexOfNone(u8, content, &std.ascii.whitespace) == null)
            return null
        else
            content;

        // alloc_always so all strings are copied into arena allocator.
        // Safely free 'content' while the returned Parsed(T) stays valid.
        return try std.json.parseFromSlice(FileConf, allocator, slice, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        });
    }

    pub fn isEmpty(content: []const u8) bool {
        const trimmed = std.mem.trim(u8, content, &std.ascii.whitespace);
        return trimmed.len == 0;
    }

    /// Loads a FileConf from a JSON file at `path`.
    /// Returns null if the file doesn't exist, or parses the file contents.
    /// If the file is empty (only whitespace), parses the default JSON instead.
    pub fn loadFromPath(allocator: std.mem.Allocator, path: []const u8) !?std.json.Parsed(FileConf) {
        const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
            error.FileNotFound => return null,
            else => return err,
        };

        defer file.close();

        const content = try file.readToEndAlloc(allocator, END_ALLOC_SIZE);
        defer allocator.free(content);

        const slice = if (std.mem.indexOfNone(u8, content, &std.ascii.whitespace) == null)
            default()
        else
            content;

        // alloc_always so all strings are copied into arena allocator.
        // Safely free 'content' while the returned Parsed(T) stays valid.
        return try std.json.parseFromSlice(FileConf, allocator, slice, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        });
    }
};
