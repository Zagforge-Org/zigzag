//! Single-file LLM report: renders the whole document into one buffer, then
//! flushes it to `llm_path`.
const std = @import("std");
const Config = @import("../../../config/Config.zig");
const ReportData = @import("../aggregator.zig").ReportData;
const Analysis = @import("Analysis.zig");
const sections = @import("sections.zig");
const VERSION = @import("../../../config/Config.zig").VERSION;

pub fn write(
    io: std.Io,
    data: *const ReportData,
    analysis: *const Analysis,
    binary_count: usize,
    llm_path: []const u8,
    root_path: []const u8,
    cfg: *const Config,
    allocator: std.mem.Allocator,
) !void {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    const w = &aw.writer;

    try w.print(
        "# LLM Context: {s}\n" ++
            "> This report is condensed for LLM ingestion. The full human-readable report is available at report.md.\n" ++
            "> ZigZag v{s} · {s}\n\n",
        .{ root_path, VERSION, data.date_str },
    );
    try sections.writeDescription(w, cfg);
    try sections.writeStatistics(w, analysis, binary_count);
    try sections.writeFileIndex(w, analysis);

    try w.writeAll("## Source\n\n");
    for (analysis.real_entries.items, analysis.file_contents.items) |entry, fc| {
        try sections.writeSourceBlock(w, entry, fc);
    }

    var llm_file = try std.Io.Dir.cwd().createFile(io, llm_path, .{ .truncate = true });
    defer llm_file.close(io);
    try llm_file.writeStreamingAll(io, aw.written());
}
