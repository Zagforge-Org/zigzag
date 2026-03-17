const std = @import("std");
const Config = @import("./config.zig").Config;
const FileConf = @import("../../../conf/file.zig").FileConf;

test "Config.default has expected defaults" {
    const allocator = std.testing.allocator;
    var cfg = Config.default(allocator);
    defer cfg.deinit();

    try std.testing.expectEqual(@as(usize, 1 << 20), cfg.small_threshold);
    try std.testing.expectEqual(@as(usize, 16 << 20), cfg.mmap_threshold);
    try std.testing.expect(!cfg.skip_cache);
    try std.testing.expect(!cfg.watch);
    try std.testing.expect(!cfg.json_output);
    try std.testing.expect(!cfg.html_output);
    try std.testing.expect(!cfg.llm_report);
    try std.testing.expectEqual(@as(u64, 150), cfg.llm_max_lines);
    try std.testing.expectEqual(@as(u16, 5455), cfg.serve_port);
    try std.testing.expect(cfg.output == null);
    try std.testing.expect(cfg.output_dir == null);
    try std.testing.expect(cfg.timezone_offset == null);
    try std.testing.expect(cfg.llm_description == null);
    try std.testing.expectEqual(@as(usize, 0), cfg.paths.items.len);
    try std.testing.expectEqual(@as(usize, 0), cfg.ignore_patterns.items.len);
}

test "Config.appendIgnorePattern adds a pattern" {
    const allocator = std.testing.allocator;
    var cfg = Config.default(allocator);
    defer cfg.deinit();

    try cfg.appendIgnorePattern("*.png");
    try std.testing.expectEqual(@as(usize, 1), cfg.ignore_patterns.items.len);
    try std.testing.expectEqualStrings("*.png", cfg.ignore_patterns.items[0]);
}

test "Config.appendIgnorePattern accumulates multiple patterns" {
    const allocator = std.testing.allocator;
    var cfg = Config.default(allocator);
    defer cfg.deinit();

    try cfg.appendIgnorePattern("*.png");
    try cfg.appendIgnorePattern("*.jpg");
    try std.testing.expectEqual(@as(usize, 2), cfg.ignore_patterns.items.len);
    try std.testing.expectEqualStrings("*.png", cfg.ignore_patterns.items[0]);
    try std.testing.expectEqualStrings("*.jpg", cfg.ignore_patterns.items[1]);
}

test "Config.appendIgnorePattern trims surrounding whitespace" {
    const allocator = std.testing.allocator;
    var cfg = Config.default(allocator);
    defer cfg.deinit();

    try cfg.appendIgnorePattern("  *.png  ");
    try std.testing.expectEqual(@as(usize, 1), cfg.ignore_patterns.items.len);
    try std.testing.expectEqualStrings("*.png", cfg.ignore_patterns.items[0]);
}

test "Config.appendIgnorePattern ignores blank and whitespace-only patterns" {
    const allocator = std.testing.allocator;
    var cfg = Config.default(allocator);
    defer cfg.deinit();

    try cfg.appendIgnorePattern("");
    try cfg.appendIgnorePattern("   ");
    try cfg.appendIgnorePattern("\t\n");
    try std.testing.expectEqual(@as(usize, 0), cfg.ignore_patterns.items.len);
}

test "Config.clearIgnorePatterns removes all patterns" {
    const allocator = std.testing.allocator;
    var cfg = Config.default(allocator);
    defer cfg.deinit();

    try cfg.appendIgnorePattern("*.png");
    try cfg.appendIgnorePattern("*.jpg");
    cfg.clearIgnorePatterns();
    try std.testing.expectEqual(@as(usize, 0), cfg.ignore_patterns.items.len);
}

test "Config.clearIgnorePatterns on empty list is a no-op" {
    const allocator = std.testing.allocator;
    var cfg = Config.default(allocator);
    defer cfg.deinit();

    cfg.clearIgnorePatterns();
    try std.testing.expectEqual(@as(usize, 0), cfg.ignore_patterns.items.len);
}

test "Config.applyFileConf sets boolean scalar fields" {
    const allocator = std.testing.allocator;
    var cfg = Config.default(allocator);
    defer cfg.deinit();

    const fc = FileConf{
        .skip_cache = true,
        .watch = true,
        .json_output = true,
        .html_output = true,
        .llm_report = true,
    };
    try cfg.applyFileConf(&fc);

    try std.testing.expect(cfg.skip_cache);
    try std.testing.expect(cfg.watch);
    try std.testing.expect(cfg.json_output);
    try std.testing.expect(cfg.html_output);
    try std.testing.expect(cfg.llm_report);
}

test "Config.applyFileConf sets numeric scalar fields" {
    const allocator = std.testing.allocator;
    var cfg = Config.default(allocator);
    defer cfg.deinit();

    const fc = FileConf{
        .small_threshold = 512,
        .mmap_threshold = 2048,
        .llm_max_lines = 300,
    };
    try cfg.applyFileConf(&fc);

    try std.testing.expectEqual(@as(usize, 512), cfg.small_threshold);
    try std.testing.expectEqual(@as(usize, 2048), cfg.mmap_threshold);
    try std.testing.expectEqual(@as(u64, 300), cfg.llm_max_lines);
}

test "Config.applyFileConf sets paths" {
    const allocator = std.testing.allocator;
    var cfg = Config.default(allocator);
    defer cfg.deinit();

    const paths = [_][]const u8{ "./src", "./lib" };
    const fc = FileConf{ .paths = &paths };
    try cfg.applyFileConf(&fc);

    try std.testing.expectEqual(@as(usize, 2), cfg.paths.items.len);
    try std.testing.expectEqualStrings("./src", cfg.paths.items[0]);
    try std.testing.expectEqualStrings("./lib", cfg.paths.items[1]);
}

test "Config.applyFileConf sets ignores" {
    const allocator = std.testing.allocator;
    var cfg = Config.default(allocator);
    defer cfg.deinit();

    const patterns = [_][]const u8{ "*.png", "node_modules" };
    const fc = FileConf{ .ignores = &patterns };
    try cfg.applyFileConf(&fc);

    try std.testing.expectEqual(@as(usize, 2), cfg.ignore_patterns.items.len);
    try std.testing.expectEqualStrings("*.png", cfg.ignore_patterns.items[0]);
    try std.testing.expectEqualStrings("node_modules", cfg.ignore_patterns.items[1]);
}

test "Config.applyFileConf sets output" {
    const allocator = std.testing.allocator;
    var cfg = Config.default(allocator);
    defer cfg.deinit();

    const fc = FileConf{ .output = "custom.md" };
    try cfg.applyFileConf(&fc);

    try std.testing.expectEqualStrings("custom.md", cfg.output.?);
}

test "Config.applyFileConf replaces output on repeated calls" {
    const allocator = std.testing.allocator;
    var cfg = Config.default(allocator);
    defer cfg.deinit();

    try cfg.applyFileConf(&FileConf{ .output = "first.md" });
    try cfg.applyFileConf(&FileConf{ .output = "second.md" });
    try std.testing.expectEqualStrings("second.md", cfg.output.?);
}

test "Config.applyFileConf sets output_dir" {
    const allocator = std.testing.allocator;
    var cfg = Config.default(allocator);
    defer cfg.deinit();

    const fc = FileConf{ .output_dir = "my-reports" };
    try cfg.applyFileConf(&fc);

    try std.testing.expectEqualStrings("my-reports", cfg.output_dir.?);
}

test "Config.applyFileConf replaces output_dir on repeated calls" {
    const allocator = std.testing.allocator;
    var cfg = Config.default(allocator);
    defer cfg.deinit();

    try cfg.applyFileConf(&FileConf{ .output_dir = "first-dir" });
    try cfg.applyFileConf(&FileConf{ .output_dir = "second-dir" });
    try std.testing.expectEqualStrings("second-dir", cfg.output_dir.?);
}

test "Config.applyFileConf does not override output_dir when set by CLI" {
    const allocator = std.testing.allocator;
    var cfg = Config.default(allocator);
    defer cfg.deinit();

    cfg.output_dir = try allocator.dupe(u8, "cli-dir");
    cfg._output_dir_allocated = true;
    cfg._output_dir_set_by_cli = true;

    const fc = FileConf{ .output_dir = "file-dir" };
    try cfg.applyFileConf(&fc);

    try std.testing.expectEqualStrings("cli-dir", cfg.output_dir.?);
}

test "Config.applyFileConf sets llm_description" {
    const allocator = std.testing.allocator;
    var cfg = Config.default(allocator);
    defer cfg.deinit();

    const fc = FileConf{ .llm_description = "A CLI scanning tool" };
    try cfg.applyFileConf(&fc);

    try std.testing.expectEqualStrings("A CLI scanning tool", cfg.llm_description.?);
}

test "Config.applyFileConf replaces llm_description on repeated calls" {
    const allocator = std.testing.allocator;
    var cfg = Config.default(allocator);
    defer cfg.deinit();

    try cfg.applyFileConf(&FileConf{ .llm_description = "first" });
    try cfg.applyFileConf(&FileConf{ .llm_description = "second" });
    try std.testing.expectEqualStrings("second", cfg.llm_description.?);
}

test "Config.applyFileConf parses positive timezone" {
    const allocator = std.testing.allocator;
    var cfg = Config.default(allocator);
    defer cfg.deinit();

    const fc = FileConf{ .timezone = "+02:00" };
    try cfg.applyFileConf(&fc);

    try std.testing.expectEqual(@as(i64, 7200), cfg.timezone_offset.?);
}

test "Config.applyFileConf parses negative timezone" {
    const allocator = std.testing.allocator;
    var cfg = Config.default(allocator);
    defer cfg.deinit();

    const fc = FileConf{ .timezone = "-05:30" };
    try cfg.applyFileConf(&fc);

    try std.testing.expectEqual(@as(i64, -(5 * 3600 + 30 * 60)), cfg.timezone_offset.?);
}

test "Config.applyFileConf null fields leave config unchanged" {
    const allocator = std.testing.allocator;
    var cfg = Config.default(allocator);
    defer cfg.deinit();

    const fc = FileConf{};
    try cfg.applyFileConf(&fc);

    try std.testing.expectEqual(@as(usize, 1 << 20), cfg.small_threshold);
    try std.testing.expect(!cfg.skip_cache);
    try std.testing.expect(cfg.output == null);
    try std.testing.expect(cfg.output_dir == null);
    try std.testing.expectEqual(@as(usize, 0), cfg.paths.items.len);
    try std.testing.expectEqual(@as(usize, 0), cfg.ignore_patterns.items.len);
}

test "applyFileConf applies ignores from FileConf" {
    const allocator = std.testing.allocator;
    var cfg = Config.default(allocator);
    defer cfg.deinit();

    const patterns: []const []const u8 = &.{ "*.png", "*.jpg" };
    const fc = FileConf{
        .ignores = patterns,
    };
    try cfg.applyFileConf(&fc);
    try std.testing.expectEqual(@as(usize, 2), cfg.ignore_patterns.items.len);
    try std.testing.expectEqualStrings("*.png", cfg.ignore_patterns.items[0]);
    try std.testing.expectEqualStrings("*.jpg", cfg.ignore_patterns.items[1]);
}
