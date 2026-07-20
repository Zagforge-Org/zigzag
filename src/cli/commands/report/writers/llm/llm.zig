//! LLM-optimised report writer. Computes a condensed analysis of the source tree
//! (see Analysis.zig), then renders it either as a single markdown file or as
//! size-bounded chunks with a manifest.
const std = @import("std");
const Config = @import("../../../config/Config.zig");
const ReportData = @import("../aggregator.zig").ReportData;
const Analysis = @import("Analysis.zig");
const Pool = @import("../../../../../workers/Pool.zig");
const single = @import("single.zig");
const chunked = @import("chunked.zig");

/// Write a condensed LLM report alongside the markdown report. When `chunk_size`
/// is non-zero the output is split into `<base>-N.md` chunks plus a manifest;
/// otherwise the whole report is written to `llm_path`.
pub fn writeLlmReport(
    io: std.Io,
    data: *const ReportData,
    binary_count: usize,
    llm_path: []const u8,
    root_path: []const u8,
    cfg: *const Config,
    chunk_size: usize,
    allocator: std.mem.Allocator,
    pool: ?*Pool,
) !void {
    var analysis = try Analysis.compute(data, cfg, allocator, pool);
    defer analysis.deinit();

    if (chunk_size > 0) {
        try chunked.write(io, data, &analysis, binary_count, llm_path, root_path, cfg, chunk_size, allocator);
    } else {
        try single.write(io, data, &analysis, binary_count, llm_path, root_path, cfg, allocator);
    }
}
