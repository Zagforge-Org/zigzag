const std = @import("std");

/// FileConf represents the structure of zig.conf.json.
/// All fields are optional — missing fields fall back to Config defaults.
pub const FileConf = struct {
    paths: ?[]const []const u8 = null,
    ignore_patterns: ?[]const []const u8 = null,
    skip_cache: ?bool = null,
    skip_git: ?bool = null,
    small_threshold: ?usize = null,
    mmap_threshold: ?usize = null,
    timezone: ?[]const u8 = null,
    output: ?[]const u8 = null,
    watch: ?bool = null,
    json_output: ?bool = null,
    html_output: ?bool = null,
    output_dir: ?[]const u8 = null,
};

pub const DEFAULT_CONF_FILENAME = "zig.conf.json";

/// Returns the default zig.conf.json content as a static string.
pub fn defaultContent() []const u8 {
    return 
    \\{
    \\  "paths": [],
    \\  "ignore_patterns": [],
    \\  "skip_cache": false,
    \\  "skip_git": false,
    \\  "small_threshold": 1048576,
    \\  "mmap_threshold": 16777216,
    \\  "timezone": null,
    \\  "output": "report.md",
    \\  "watch": false,
    \\  "json_output": false,
    \\  "html_output": false
    \\}
    \\
    ;
}

/// Loads and parses zig.conf.json from the current working directory.
/// Returns null if the file does not exist or is empty.
/// Returns an error if the file exists but cannot be parsed.
pub fn load(allocator: std.mem.Allocator) !?std.json.Parsed(FileConf) {
    return loadFromPath(allocator, DEFAULT_CONF_FILENAME);
}

/// Loads and parses a JSON config file from the given path.
/// Returns null if the file does not exist or is empty.
pub fn loadFromPath(allocator: std.mem.Allocator, path: []const u8) !?std.json.Parsed(FileConf) {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1 << 20); // 1 MiB max
    defer allocator.free(content);

    // Treat empty files as if the file doesn't exist
    if (std.mem.trim(u8, content, " \t\n\r").len == 0) return null;

    // Use alloc_always so all strings are copied into the arena allocator.
    // This lets us safely free `content` while the returned Parsed(T) stays valid.
    return try std.json.parseFromSlice(FileConf, allocator, content, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
}

test "loadFromPath returns null for non-existent file" {
    const allocator = std.testing.allocator;
    const result = try loadFromPath(allocator, "/nonexistent/zztest_does_not_exist.json");
    try std.testing.expect(result == null);
}

test "loadFromPath returns null for empty file" {
    const allocator = std.testing.allocator;
    const tmp_path = "zztest_conf_empty_file.json";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        f.close();
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const result = try loadFromPath(allocator, tmp_path);
    try std.testing.expect(result == null);
}

test "loadFromPath parses valid JSON with all fields" {
    const allocator = std.testing.allocator;
    const tmp_path = "zztest_conf_full.json";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll(
            \\{"paths": ["./src"], "skip_cache": true, "watch": false}
        );
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const result = try loadFromPath(allocator, tmp_path);
    try std.testing.expect(result != null);

    var parsed = result.?;
    defer parsed.deinit();

    try std.testing.expect(parsed.value.paths != null);
    try std.testing.expectEqual(@as(usize, 1), parsed.value.paths.?.len);
    try std.testing.expectEqualStrings("./src", parsed.value.paths.?[0]);
    try std.testing.expect(parsed.value.skip_cache.? == true);
    try std.testing.expect(parsed.value.watch.? == false);
}

test "loadFromPath handles empty JSON object" {
    const allocator = std.testing.allocator;
    const tmp_path = "zztest_conf_empty_obj.json";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("{}");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const result = try loadFromPath(allocator, tmp_path);
    try std.testing.expect(result != null);

    var parsed = result.?;
    defer parsed.deinit();

    try std.testing.expect(parsed.value.paths == null);
    try std.testing.expect(parsed.value.ignore_patterns == null);
    try std.testing.expect(parsed.value.skip_cache == null);
    try std.testing.expect(parsed.value.watch == null);
    try std.testing.expect(parsed.value.output == null);
}

test "loadFromPath handles ignore_patterns array" {
    const allocator = std.testing.allocator;
    const tmp_path = "zztest_conf_patterns.json";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll(
            \\{"ignore_patterns": ["*.png", "*.jpg", "node_modules"]}
        );
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const result = try loadFromPath(allocator, tmp_path);
    try std.testing.expect(result != null);

    var parsed = result.?;
    defer parsed.deinit();

    try std.testing.expect(parsed.value.ignore_patterns != null);
    try std.testing.expectEqual(@as(usize, 3), parsed.value.ignore_patterns.?.len);
    try std.testing.expectEqualStrings("*.png", parsed.value.ignore_patterns.?[0]);
    try std.testing.expectEqualStrings("*.jpg", parsed.value.ignore_patterns.?[1]);
    try std.testing.expectEqualStrings("node_modules", parsed.value.ignore_patterns.?[2]);
}

test "defaultContent is valid parseable JSON" {
    const allocator = std.testing.allocator;
    const content = defaultContent();
    const parsed = try std.json.parseFromSlice(FileConf, allocator, content, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    try std.testing.expect(parsed.value.paths != null);
    try std.testing.expectEqual(@as(usize, 0), parsed.value.paths.?.len);
    try std.testing.expect(parsed.value.skip_cache.? == false);
    try std.testing.expect(parsed.value.watch.? == false);
    try std.testing.expectEqualStrings("report.md", parsed.value.output.?);
}

test "defaultContent includes json_output field set to false" {
    const allocator = std.testing.allocator;
    const content = defaultContent();
    const parsed = try std.json.parseFromSlice(FileConf, allocator, content, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    try std.testing.expect(parsed.value.json_output != null);
    try std.testing.expect(parsed.value.json_output.? == false);
}

test "loadFromPath parses json_output true" {
    const allocator = std.testing.allocator;
    const tmp_path = "zztest_conf_json_output_true.json";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("{\"json_output\": true}");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const result = try loadFromPath(allocator, tmp_path);
    try std.testing.expect(result != null);
    var parsed = result.?;
    defer parsed.deinit();
    try std.testing.expect(parsed.value.json_output.? == true);
}

test "defaultContent includes html_output field set to false" {
    const allocator = std.testing.allocator;
    const content = defaultContent();
    const parsed = try std.json.parseFromSlice(FileConf, allocator, content, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    try std.testing.expect(parsed.value.html_output != null);
    try std.testing.expect(parsed.value.html_output.? == false);
}

test "loadFromPath parses html_output true" {
    const allocator = std.testing.allocator;
    const tmp_path = "zztest_conf_html_output_true.json";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("{\"html_output\": true}");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const result = try loadFromPath(allocator, tmp_path);
    try std.testing.expect(result != null);
    var parsed = result.?;
    defer parsed.deinit();
    try std.testing.expect(parsed.value.html_output.? == true);
}

test "loadFromPath sets json_output to null when field is absent" {
    const allocator = std.testing.allocator;
    const tmp_path = "zztest_conf_json_output_absent.json";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("{\"skip_cache\": true}");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const result = try loadFromPath(allocator, tmp_path);
    try std.testing.expect(result != null);
    var parsed = result.?;
    defer parsed.deinit();
    try std.testing.expect(parsed.value.json_output == null);
}

test "loadFromPath ignores unknown JSON fields" {
    const allocator = std.testing.allocator;
    const tmp_path = "zztest_conf_unknown.json";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll(
            \\{"unknown_field": true, "another_unknown": 42, "watch": true}
        );
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const result = try loadFromPath(allocator, tmp_path);
    try std.testing.expect(result != null);

    var parsed = result.?;
    defer parsed.deinit();

    try std.testing.expect(parsed.value.watch.? == true);
}

test "loadFromPath parses output_dir field" {
    const allocator = std.testing.allocator;
    const tmp_path = "zztest_conf_output_dir.json";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("{\"output_dir\": \"my-reports\"}");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const result = try loadFromPath(allocator, tmp_path);
    try std.testing.expect(result != null);
    var parsed = result.?;
    defer parsed.deinit();
    try std.testing.expectEqualStrings("my-reports", parsed.value.output_dir.?);
}
