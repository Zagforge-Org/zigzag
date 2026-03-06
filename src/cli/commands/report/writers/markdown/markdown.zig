const std = @import("std");
const Config = @import("../../../config/config.zig").Config;
const JobEntry = @import("../../../../../jobs/entry.zig").JobEntry;
const BinaryEntry = @import("../../../../../jobs/entry.zig").BinaryEntry;
const ReportData = @import("../aggregator.zig").ReportData;

/// Write a single file entry to the report with metadata.
fn writeFileEntry(
    md_file: *std.fs.File,
    entry: *const JobEntry,
    allocator: std.mem.Allocator,
    timezone_offset: ?i64,
) !void {
    const size_str = try entry.formatSize(allocator);
    defer allocator.free(size_str);

    const mtime_str = try entry.formatMtime(allocator, timezone_offset);
    defer allocator.free(mtime_str);

    const lang = entry.getLanguage();

    const header = try std.fmt.allocPrint(
        allocator,
        "## File: `{s}`\n\n" ++
            "**Metadata:**\n" ++
            "- **Size:** {s}\n" ++
            "- **Language:** {s}\n" ++
            "- **Last Modified:** {s}\n\n",
        .{
            entry.path,
            size_str,
            if (lang.len > 0) lang else "unknown",
            mtime_str,
        },
    );
    defer allocator.free(header);
    try md_file.writeAll(header);

    const code_fence_start = if (lang.len > 0)
        try std.fmt.allocPrint(allocator, "```{s}\n", .{lang})
    else
        try allocator.dupe(u8, "```\n");
    defer allocator.free(code_fence_start);

    try md_file.writeAll(code_fence_start);
    try md_file.writeAll(entry.content);

    if (entry.content.len > 0 and entry.content[entry.content.len - 1] != '\n') {
        try md_file.writeAll("\n");
    }

    try md_file.writeAll("```\n\n");
}

/// Serialize pre-aggregated data to a markdown report file.
/// Called both from one-shot mode and watch mode.
pub fn writeReport(
    data: *const ReportData,
    file_entries: *const std.StringHashMap(JobEntry),
    md_path: []const u8,
    root_path: []const u8,
    cfg: *const Config,
    allocator: std.mem.Allocator,
) !void {
    const output_filename = std.fs.path.basename(md_path);
    std.log.info("Building {s} for {s}...", .{ output_filename, root_path });

    var md_file = try std.fs.cwd().createFile(md_path, .{ .truncate = true });
    defer md_file.close();

    // Header
    const header = try std.fmt.allocPrint(
        allocator,
        "# Code Report for: `{s}`\n\n" ++
            "Generated on: {s}\n\n" ++
            "---\n\n",
        .{ root_path, data.generated_at_str },
    );
    defer allocator.free(header);
    try md_file.writeAll(header);

    // Table of contents (built from the raw map for correct entry paths)
    try md_file.writeAll("## Table of Contents\n\n");

    var toc_list: std.ArrayList([]const u8) = .empty;
    defer {
        for (toc_list.items) |item| allocator.free(item);
        toc_list.deinit(allocator);
    }

    var it = file_entries.iterator();
    while (it.next()) |entry| {
        const toc_entry = try std.fmt.allocPrint(allocator, "- [{s}](#{s})\n", .{
            entry.value_ptr.path,
            entry.value_ptr.path,
        });
        try toc_list.append(allocator, toc_entry);
    }

    std.mem.sort([]const u8, toc_list.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    for (toc_list.items) |toc_entry| try md_file.writeAll(toc_entry);
    try md_file.writeAll("\n---\n\n");

    // Sorted file entries (use pre-sorted list from ReportData)
    for (data.sorted_files.items) |*entry| {
        try writeFileEntry(&md_file, entry, allocator, cfg.timezone_offset);
    }
}
