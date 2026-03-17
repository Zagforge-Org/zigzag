const FileConf = @import("./file.zig").FileConf;
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

    var wbuf1: [512]u8 = undefined;
    var fw1 = f.writer(&wbuf1);
    try fw1.interface.writeAll(
        \\{"paths": ["./src"], "skip_cache": true, "watch": false}
    );
    try fw1.interface.flush();

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
        var wbuf2: [8]u8 = undefined;
        var fw2 = f.writer(&wbuf2);
        try fw2.interface.writeAll("{}");
        try fw2.interface.flush();
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const result = try FileConf.loadFromPathEmpty(allocator, tmp_path);
    try std.testing.expect(result != null);

    var parsed = result.?;
    defer parsed.deinit();

    try std.testing.expect(parsed.value.paths == null);
    try std.testing.expect(parsed.value.ignores == null);
    try std.testing.expect(parsed.value.skip_cache == null);
    try std.testing.expect(parsed.value.watch == null);
    try std.testing.expect(parsed.value.output == null);
}

test "loadFromPath handles ignores array" {
    const allocator = std.testing.allocator;
    const tmp_path = "zztest_conf_patterns.json";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        var wbuf3: [512]u8 = undefined;
        var fw3 = f.writer(&wbuf3);
        try fw3.interface.writeAll(
            \\{"ignores": ["*.png", "*.jpg", "node_modules"]}
        );
        try fw3.interface.flush();
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const result = try FileConf.loadFromPathEmpty(allocator, tmp_path);
    try std.testing.expect(result != null);

    var parsed = result.?;
    defer parsed.deinit();

    try std.testing.expect(parsed.value.ignores != null);
    try std.testing.expectEqual(@as(usize, 3), parsed.value.ignores.?.len);
    try std.testing.expectEqualStrings("*.png", parsed.value.ignores.?[0]);
    try std.testing.expectEqualStrings("*.jpg", parsed.value.ignores.?[1]);
    try std.testing.expectEqualStrings("node_modules", parsed.value.ignores.?[2]);
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
        var wbuf4: [64]u8 = undefined;
        var fw4 = f.writer(&wbuf4);
        try fw4.interface.writeAll("{\"json_output\": true}");
        try fw4.interface.flush();
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
        var wbuf5: [64]u8 = undefined;
        var fw5 = f.writer(&wbuf5);
        try fw5.interface.writeAll("{\"html_output\": true}");
        try fw5.interface.flush();
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
        var wbuf6: [64]u8 = undefined;
        var fw6 = f.writer(&wbuf6);
        try fw6.interface.writeAll("{\"skip_cache\": true}");
        try fw6.interface.flush();
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
        var wbuf7: [512]u8 = undefined;
        var fw7 = f.writer(&wbuf7);
        try fw7.interface.writeAll(
            \\{"unknown_field": true, "another_unknown": 42, "watch": true}
        );
        try fw7.interface.flush();
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
        var wbuf8: [64]u8 = undefined;
        var fw8 = f.writer(&wbuf8);
        try fw8.interface.writeAll("{\"output_dir\": \"my-reports\"}");
        try fw8.interface.flush();
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
        var wbuf9: [64]u8 = undefined;
        var fw9 = f.writer(&wbuf9);
        try fw9.interface.writeAll("{\"llm_report\": true}");
        try fw9.interface.flush();
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
        var wbuf10: [64]u8 = undefined;
        var fw10 = f.writer(&wbuf10);
        try fw10.interface.writeAll("{\"llm_max_lines\": 200}");
        try fw10.interface.flush();
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
        var wbuf11: [64]u8 = undefined;
        var fw11 = f.writer(&wbuf11);
        try fw11.interface.writeAll("{\"llm_description\": \"A CLI tool\"}");
        try fw11.interface.flush();
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

test "writeDefaultConfig writes FileConf.default() to file" {
    const tmp_path = "zztest_conf_write_default.json";

    // Ensure file cleanup at the end
    defer std.fs.cwd().deleteFile(tmp_path) catch |err| {
        std.log.warn("failed to delete file: {}", .{err});
    };

    // Write default config
    try FileConf.writeDefaultConfig(tmp_path);

    // Read all contents
    const file_contents = try std.fs.cwd().readFileAlloc(std.testing.allocator, tmp_path, 4096);
    defer std.testing.allocator.free(file_contents);

    // Compare the contents with FileConf.default()
    try std.testing.expectEqualStrings(FileConf.default(), file_contents);
}

test "FileConf deserialises 'ignores' key" {
    const allocator = std.testing.allocator;
    const tmp_path = "zztest_conf_ignores_key.json";
    const f = try std.fs.cwd().createFile(tmp_path, .{});
    defer std.fs.cwd().deleteFile(tmp_path) catch {};
    defer f.close();
    try f.writeAll(
        \\{"ignores": ["*.png", "*.jpg"]}
    );
    const result = try FileConf.loadFromPath(allocator, tmp_path);
    try std.testing.expect(result != null);
    defer result.?.deinit();
    const conf = result.?.value;
    try std.testing.expect(conf.ignores != null);
    try std.testing.expectEqual(@as(usize, 2), conf.ignores.?.len);
    try std.testing.expectEqualStrings("*.png", conf.ignores.?[0]);
    try std.testing.expectEqualStrings("*.jpg", conf.ignores.?[1]);
}

test "FileConf old 'ignore_patterns' key is silently ignored" {
    const allocator = std.testing.allocator;
    const tmp_path = "zztest_conf_old_ignore_patterns.json";
    const f = try std.fs.cwd().createFile(tmp_path, .{});
    defer std.fs.cwd().deleteFile(tmp_path) catch {};
    defer f.close();
    try f.writeAll(
        \\{"ignore_patterns": ["*.png"]}
    );
    const result = try FileConf.loadFromPath(allocator, tmp_path);
    try std.testing.expect(result != null);
    defer result.?.deinit();
    // Old key is unknown field — parsed as null
    try std.testing.expect(result.?.value.ignores == null);
}
