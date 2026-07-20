const std = @import("std");
const Config = @import("../../../config/Config.zig");
const JobEntry = @import("../../../../../jobs/entries.zig").JobEntry;
const BinaryEntry = @import("../../../../../jobs/entries.zig").BinaryEntry;
const ReportData = @import("../aggregator.zig").ReportData;

/// Write a single file entry to the report with metadata.
fn writeFileEntry(
    io: std.Io,
    md_file: *std.Io.File,
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
    try md_file.writeStreamingAll(io, header);

    const code_fence_start = if (lang.len > 0)
        try std.fmt.allocPrint(allocator, "```{s}\n", .{lang})
    else
        try allocator.dupe(u8, "```\n");
    defer allocator.free(code_fence_start);

    try md_file.writeStreamingAll(io, code_fence_start);
    try md_file.writeStreamingAll(io, entry.content);

    if (entry.content.len > 0 and entry.content[entry.content.len - 1] != '\n') {
        try md_file.writeStreamingAll(io, "\n");
    }

    try md_file.writeStreamingAll(io, "```\n\n");
}

/// Serialize pre-aggregated data to a markdown report file.
/// Called both from one-shot mode and watch mode. Reads only the ReportData
/// snapshot so it can run while the live entry maps are being updated.
pub fn writeReport(
    io: std.Io,
    data: *const ReportData,
    md_path: []const u8,
    root_path: []const u8,
    cfg: *const Config,
    allocator: std.mem.Allocator,
) !void {
    var md_file = try std.Io.Dir.cwd().createFile(io, md_path, .{ .truncate = true });
    defer md_file.close(io);

    // Header
    const header = try std.fmt.allocPrint(
        allocator,
        "# Code Report for: `{s}`\n\n" ++
            "Generated on: {s}\n\n" ++
            "---\n\n",
        .{ root_path, data.generated_at_str },
    );
    defer allocator.free(header);
    try md_file.writeStreamingAll(io, header);

    // Table of contents (sorted_files is already path-ordered)
    try md_file.writeStreamingAll(io, "## Table of Contents\n\n");

    for (data.sorted_files.items) |*entry| {
        const toc_entry = try std.fmt.allocPrint(allocator, "- [{s}](#{s})\n", .{ entry.path, entry.path });
        defer allocator.free(toc_entry);
        try md_file.writeStreamingAll(io, toc_entry);
    }
    try md_file.writeStreamingAll(io, "\n---\n\n");

    // Sorted file entries (use pre-sorted list from ReportData)
    for (data.sorted_files.items) |*entry| {
        try writeFileEntry(io, &md_file, entry, allocator, cfg.timezone_offset);
    }
}
