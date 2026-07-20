//! Shared markdown section writers for the LLM report.

const std = @import("std");
const Config = @import("../../../config/Config.zig");
const JobEntry = @import("../../../../../jobs/entries.zig").JobEntry;
const Analysis = @import("Analysis.zig");
const FileContent = Analysis.FileContent;

/// Lines shown per condensed file.
pub const shown_lines: usize = 80;

/// `## Project Description` block, emitted only when a non-empty description is set.
pub fn writeDescription(w: *std.Io.Writer, cfg: *const Config) !void {
    const desc = cfg.llm_description orelse return;
    if (desc.len == 0) return;
    try w.print("## Project Description\n{s}\n\n", .{desc});
}

pub fn writeStatistics(w: *std.Io.Writer, analysis: *const Analysis, binary_count: usize) !void {
    try w.writeAll("## Statistics\n");
    try w.print(
        "- Source files: {d}  |  Binary files: {d}  |  Boilerplate skipped: {d}\n",
        .{ analysis.real_entries.items.len, binary_count, analysis.boilerplate_count },
    );
    if (analysis.lang_list.items.len > 0) {
        try w.writeAll("- Languages: ");
        for (analysis.lang_list.items, 0..) |lc, i| {
            if (i > 0) try w.writeAll(", ");
            try w.print("{s} ({d})", .{ lc.name, lc.count });
        }
        try w.writeByte('\n');
    }
    try w.print(
        "- Original lines: {d}  →  Condensed: ~{d}  ({d}% reduction)\n\n",
        .{ analysis.original_lines, analysis.condensed_lines, analysis.reductionPct() },
    );
}

pub fn writeFileIndex(w: *std.Io.Writer, analysis: *const Analysis) !void {
    try w.writeAll("## File Index\n");
    for (analysis.real_entries.items, analysis.file_contents.items) |entry, fc| {
        switch (fc) {
            .ast => |chunks| try w.print("- {s} ({d} AST chunks)\n", .{ entry.path, chunks.len }),
            .condensed => |condensed| if (isCondensed(condensed)) {
                try w.print("- {s} (condensed — {d} of {d} lines shown)\n", .{ entry.path, shown_lines, entry.line_count });
            } else {
                try w.print("- {s} ({d} lines, full)\n", .{ entry.path, entry.line_count });
            },
        }
    }
    try w.writeByte('\n');
}

/// Render one file's `### heading` plus fenced body.
pub fn writeSourceBlock(w: *std.Io.Writer, entry: JobEntry, fc: FileContent) !void {
    const lang = entry.getLanguage();
    switch (fc) {
        .ast => |chunks| for (chunks) |chunk| {
            try w.print("### {s} [{d}–{d}]\n", .{ entry.path, chunk.start_line + 1, chunk.end_line + 1 });
            try writeFence(w, lang);
            try writeFencedBody(w, getLineRange(entry.content, chunk.start_line, chunk.end_line));
        },
        .condensed => |condensed| {
            if (isCondensed(condensed)) {
                try w.print("### {s} *(condensed — {d} of {d} lines shown)*\n", .{ entry.path, shown_lines, entry.line_count });
            } else {
                try w.print("### {s}\n", .{entry.path});
            }
            try writeFence(w, lang);
            try writeFencedBody(w, condensed);
        },
    }
}

pub fn isCondensed(s: []const u8) bool {
    return std.mem.indexOf(u8, s, " lines omitted]") != null;
}

fn writeFence(w: *std.Io.Writer, lang: []const u8) !void {
    if (lang.len > 0) {
        try w.print("```{s}\n", .{lang});
    } else {
        try w.writeAll("```\n");
    }
}

/// Write `body`, ensure it ends in a newline, then close the fence.
fn writeFencedBody(w: *std.Io.Writer, body: []const u8) !void {
    try w.writeAll(body);
    if (body.len > 0 and body[body.len - 1] != '\n') try w.writeByte('\n');
    try w.writeAll("```\n\n");
}

/// Slice of lines [start_line..=end_line] (0-based) within `content`.
fn getLineRange(content: []const u8, start_line: u32, end_line: u32) []const u8 {
    var line: u32 = 0;
    var i: usize = 0;
    while (i < content.len and line < start_line) : (i += 1) {
        if (content[i] == '\n') line += 1;
    }
    const start_byte = i;
    while (i < content.len and line <= end_line) : (i += 1) {
        if (content[i] == '\n') line += 1;
    }
    return content[start_byte..i];
}
