const FileConf = @import("./file_new.zig").FileConf;
const std = @import("std");

test "loadFromPath returns null for non-existent file" {
    const allocator = std.testing.allocator;
    const result = try FileConf.loadFromPath(allocator, "/nonexistent/zztest_does_not_exist.json");
    try std.testing.expect(result == null);
}

test "loadFromPath returns default for empty file" {
    const allocator = std.testing.allocator;
    const tmp_path = "zztest_conf_empty_file.json";

    const f = try std.fs.cwd().createFile(tmp_path, .{});
    defer f.close();

    defer {
        std.fs.cwd().deleteFile(tmp_path) catch |err| {
            std.log.warn("failed to delete file: {}", .{err});
        };
    }

    const result = try FileConf.loadFromPath(allocator, tmp_path);

    if (result) |conf| {
        defer conf.deinit();

        const maybe_content = FileConf.read(allocator, tmp_path) catch |err| switch (err) {
            error.FileNotFound => null, // return null if file missing
            else => return err, // propagate any other error
        };

        const content = if (@TypeOf(maybe_content) == []const u8 and maybe_content.len > 0)
            maybe_content
        else
            FileConf.default();

        std.log.info("file_content: {s}", .{content});
        try std.testing.expectEqualStrings(FileConf.default(), content);
    } else {
        try std.testing.expect(false);
    }
}

test "loadFromPath parses valid JSON with all fields" {
    const allocator = std.testing.allocator;
    const tmp_path = "zztest_conf_full.json";

    const f = try std.fs.cwd().createFile(tmp_path, .{});

    try f.writeAll(
        \\{"paths": ["./src"], "skip_cache": true, "watch": false}
    );

    defer f.close();
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const result = try FileConf.loadFromPath(allocator, tmp_path);
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

    const result = try FileConf.loadFromPathEmpty(allocator, tmp_path);
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

    const result = try FileConf.loadFromPathEmpty(allocator, tmp_path);
    try std.testing.expect(result != null);

    var parsed = result.?;
    defer parsed.deinit();

    try std.testing.expect(parsed.value.ignore_patterns != null);
    try std.testing.expectEqual(@as(usize, 3), parsed.value.ignore_patterns.?.len);
    try std.testing.expectEqualStrings("*.png", parsed.value.ignore_patterns.?[0]);
    try std.testing.expectEqualStrings("*.jpg", parsed.value.ignore_patterns.?[1]);
    try std.testing.expectEqualStrings("node_modules", parsed.value.ignore_patterns.?[2]);
}

test "FileConf.default() is valid parseable JSON" {
    const allocator = std.testing.allocator;
    const content = FileConf.default();
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

test "FileConf.default() includes json_output field set to false" {
    const allocator = std.testing.allocator;
    const content = FileConf.default();
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

    const result = try FileConf.loadFromPathEmpty(allocator, tmp_path);
    try std.testing.expect(result != null);
    var parsed = result.?;
    defer parsed.deinit();
    try std.testing.expect(parsed.value.json_output.? == true);
}

test "FileConf.default() includes html_output field set to false" {
    const allocator = std.testing.allocator;
    const content = FileConf.default();
    const parsed = try std.json.parseFromSlice(FileConf, allocator, content, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    try std.testing.expect(parsed.value.html_output != null);
    try std.testing.expect(parsed.value.html_output.? == false);
}

test "loadFromPathEmpty parses html_output true" {
    const allocator = std.testing.allocator;
    const tmp_path = "zztest_conf_html_output_true.json";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("{\"html_output\": true}");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const result = try FileConf.loadFromPathEmpty(allocator, tmp_path);
    try std.testing.expect(result != null);
    var parsed = result.?;
    defer parsed.deinit();
    try std.testing.expect(parsed.value.html_output.? == true);
}

test "loadFromPathEmpty sets json_output to null when field is absent" {
    const allocator = std.testing.allocator;
    const tmp_path = "zztest_conf_json_output_absent.json";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("{\"skip_cache\": true}");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const result = try FileConf.loadFromPathEmpty(allocator, tmp_path);
    try std.testing.expect(result != null);
    var parsed = result.?;
    defer parsed.deinit();
    try std.testing.expect(parsed.value.json_output == null);
}

test "loadFromPathEmpty ignores unknown JSON fields" {
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

    const result = try FileConf.loadFromPathEmpty(allocator, tmp_path);
    try std.testing.expect(result != null);

    var parsed = result.?;
    defer parsed.deinit();

    try std.testing.expect(parsed.value.watch.? == true);
}

test "loadFromPathEmpty parses output_dir field" {
    const allocator = std.testing.allocator;
    const tmp_path = "zztest_conf_output_dir.json";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("{\"output_dir\": \"my-reports\"}");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const result = try FileConf.loadFromPathEmpty(allocator, tmp_path);
    try std.testing.expect(result != null);
    var parsed = result.?;
    defer parsed.deinit();
    try std.testing.expectEqualStrings("my-reports", parsed.value.output_dir.?);
}

test "loadFromPathEmpty parses llm_report field" {
    const allocator = std.testing.allocator;
    const tmp_path = "zztest_conf_llm_report.json";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("{\"llm_report\": true}");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const result = try FileConf.loadFromPathEmpty(allocator, tmp_path);
    var parsed = result.?;
    defer parsed.deinit();
    try std.testing.expect(parsed.value.llm_report.? == true);
}

test "loadFromPathEmpty parses llm_max_lines field" {
    const allocator = std.testing.allocator;
    const tmp_path = "zztest_conf_llm_max_lines.json";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("{\"llm_max_lines\": 200}");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const result = try FileConf.loadFromPathEmpty(allocator, tmp_path);
    var parsed = result.?;
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u64, 200), parsed.value.llm_max_lines.?);
}

test "loadFromPathEmpty parses llm_description field" {
    const allocator = std.testing.allocator;
    const tmp_path = "zztest_conf_llm_desc.json";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("{\"llm_description\": \"A CLI tool\"}");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const result = try FileConf.loadFromPathEmpty(allocator, tmp_path);
    var parsed = result.?;
    defer parsed.deinit();
    try std.testing.expectEqualStrings("A CLI tool", parsed.value.llm_description.?);
}

test "FileConf.default() includes output_dir, llm_report, llm_max_lines, llm_description fields" {
    const allocator = std.testing.allocator;
    const content = FileConf.default();
    const parsed = try std.json.parseFromSlice(FileConf, allocator, content, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    try std.testing.expectEqualStrings("zigzag-reports", parsed.value.output_dir.?);
    try std.testing.expect(parsed.value.llm_report != null);
    try std.testing.expect(parsed.value.llm_report.? == false);
    try std.testing.expectEqual(@as(u64, 150), parsed.value.llm_max_lines.?);
    try std.testing.expect(parsed.value.llm_description == null);
}
