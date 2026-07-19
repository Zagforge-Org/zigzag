//! Declarative phase table for the final report.

const FinalSummary = @import("FinalSummary.zig");

const Phase = @This();

id: Id,
display: []const u8,
highlight: []const u8,

pub const Id = enum {
    scan,
    aggregate,
    write_md,
    write_json,
    write_html,
    write_llm,
};

/// Every phase, in display order.
pub const all = [_]Phase{
    .{ .id = .scan, .display = "Scan", .highlight = "scan" },
    .{ .id = .aggregate, .display = "Aggregate", .highlight = "aggregation" },
    .{ .id = .write_md, .display = "Write Markdown", .highlight = "markdown writing" },
    .{ .id = .write_json, .display = "Write JSON", .highlight = "JSON writing" },
    .{ .id = .write_html, .display = "Write HTML", .highlight = "HTML writing" },
    .{ .id = .write_llm, .display = "Write LLM", .highlight = "LLM writing" },
};

/// Elapsed nanoseconds for `id`, read from its FinalSummary field.
pub fn elapsed(id: Id, data: *const FinalSummary) u64 {
    return switch (id) {
        .scan => data.scan_ns,
        .aggregate => data.aggregate_ns,
        .write_md => data.write_md_ns,
        .write_json => data.write_json_ns,
        .write_html => data.write_html_ns,
        .write_llm => data.write_llm_ns,
    };
}
