//! Condensed per-file analysis for the LLM report.

const std = @import("std");
const Config = @import("../../../config/Config.zig");
const JobEntry = @import("../../../../../jobs/entries.zig").JobEntry;
const ReportData = @import("../aggregator.zig").ReportData;
const content_mod = @import("../content.zig");
const ast_chunker = @import("../ast/ast_chunker.zig");
const Pool = @import("../../../../../workers/Pool.zig");
const WaitGroup = @import("../../../../../workers/WaitGroup.zig");

/// A real file's condensed representation.
pub const FileContent = union(enum) {
    condensed: []u8,
    ast: []ast_chunker.Chunk,
};

pub const LangCount = struct { name: []const u8, count: usize };

const Self = @This();

allocator: std.mem.Allocator,
real_entries: std.ArrayList(JobEntry),
file_contents: std.ArrayList(FileContent),
lang_list: std.ArrayList(LangCount),
boilerplate_count: usize,
original_lines: u64,
condensed_lines: u64,

pub fn compute(data: *const ReportData, cfg: *const Config, allocator: std.mem.Allocator, pool: ?*Pool) !Self {
    var real_entries: std.ArrayList(JobEntry) = .empty;
    errdefer real_entries.deinit(allocator);

    var boilerplate_count: usize = 0;
    for (data.sorted_files.items) |entry| {
        if (content_mod.isBoilerplate(std.fs.path.basename(entry.path))) {
            boilerplate_count += 1;
        } else {
            try real_entries.append(allocator, entry);
        }
    }

    var file_contents: std.ArrayList(FileContent) = .empty;
    errdefer freeFileContents(allocator, &file_contents);

    // Per-file condensing runs tree-sitter over every file.
    // By far the most expensive part of the LLM report.
    // Fan it out across the pool when available each job writes only its own slot,
    // so no synchronization is needed.
    if (pool) |p| {
        const slots = try allocator.alloc(?FileContent, real_entries.items.len);
        defer allocator.free(slots);
        @memset(slots, null);

        var wg = WaitGroup.init(p.io);
        for (real_entries.items, slots) |*entry, *slot| {
            p.spawn(&wg, condenseJob, .{ entry, slot, cfg.llm_max_lines, allocator }) catch {};
        }
        wg.wait();

        for (real_entries.items, slots) |*entry, *slot| {
            if (slot.*) |fc| {
                try file_contents.append(allocator, fc);
            } else {
                // Job failed or couldn't be queued; condense inline.
                try file_contents.append(allocator, try condenseEntry(entry, cfg.llm_max_lines, allocator));
            }
        }
    } else {
        for (real_entries.items) |*entry| {
            try file_contents.append(allocator, try condenseEntry(entry, cfg.llm_max_lines, allocator));
        }
    }

    var lang_map = std.StringHashMap(usize).init(allocator);
    defer lang_map.deinit();

    var original_lines: u64 = 0;
    var condensed_lines: u64 = 0;

    for (real_entries.items, file_contents.items) |*entry, fc| {
        original_lines += @intCast(entry.line_count);
        switch (fc) {
            .ast => |chunks| for (chunks) |chunk| {
                condensed_lines += (chunk.end_line - chunk.start_line) + 1;
            },
            .condensed => |s| condensed_lines += @intCast(std.mem.count(u8, s, "\n")),
        }

        const lang = entry.getLanguage();
        if (lang.len > 0) {
            const gop = try lang_map.getOrPut(lang);
            if (!gop.found_existing) gop.value_ptr.* = 0;
            gop.value_ptr.* += 1;
        }
    }

    var lang_list: std.ArrayList(LangCount) = .empty;
    errdefer lang_list.deinit(allocator);
    var it = lang_map.iterator();
    while (it.next()) |kv| {
        try lang_list.append(allocator, .{ .name = kv.key_ptr.*, .count = kv.value_ptr.* });
    }
    std.mem.sort(LangCount, lang_list.items, {}, langLessThan);

    return .{
        .allocator = allocator,
        .real_entries = real_entries,
        .file_contents = file_contents,
        .lang_list = lang_list,
        .boilerplate_count = boilerplate_count,
        .original_lines = original_lines,
        .condensed_lines = condensed_lines,
    };
}

pub fn deinit(self: *Self) void {
    freeFileContents(self.allocator, &self.file_contents);
    self.real_entries.deinit(self.allocator);
    self.lang_list.deinit(self.allocator);
}

/// Percentage of source lines dropped by condensing (0 when it grew or was empty).
pub fn reductionPct(self: *const Self) u64 {
    if (self.original_lines == 0 or self.condensed_lines > self.original_lines) return 0;
    return 100 * (self.original_lines - self.condensed_lines) / self.original_lines;
}

fn freeFileContents(allocator: std.mem.Allocator, list: *std.ArrayList(FileContent)) void {
    for (list.items) |fc| switch (fc) {
        .condensed => |s| allocator.free(s),
        .ast => |chunks| allocator.free(chunks),
    };
    list.deinit(allocator);
}

fn langLessThan(_: void, a: LangCount, b: LangCount) bool {
    if (a.count != b.count) return a.count > b.count;
    return std.mem.lessThan(u8, a.name, b.name);
}

/// AST-chunk the entry, falling back to comment-stripping condense.
/// Results are allocated with `allocator` (not a worker arena) — they outlive the job.
fn condenseEntry(entry: *const JobEntry, max_lines: u64, allocator: std.mem.Allocator) !FileContent {
    if (try ast_chunker.chunkSource(entry.content, entry.extension, allocator)) |chunks| {
        return .{ .ast = chunks };
    }
    const condensed = try content_mod.condenseContent(allocator, entry.content, entry.extension, max_lines);
    return .{ .condensed = condensed };
}

/// Pool job: condense one entry into its slot. A failed slot stays null and is
/// retried inline by compute().
fn condenseJob(entry: *const JobEntry, slot: *?FileContent, max_lines: u64, allocator: std.mem.Allocator, _: Pool.JobContext) !void {
    slot.* = try condenseEntry(entry, max_lines, allocator);
}
