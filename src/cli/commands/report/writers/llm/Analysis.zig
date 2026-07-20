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

/// Cross-flush cache of condensed results keyed by path, valid while the file's
/// mtime is unchanged. Owned by the watch State so a debounce flush re-condenses
/// only changed files instead of the whole tree. This also keeps memory flat:
/// without it every flush reallocates the full condensed set (~100 MB on large
/// repos), which caching allocators never return to the OS.
pub const Memo = struct {
    const MemoEntry = struct { mtime: i128, fc: FileContent };

    allocator: std.mem.Allocator,
    map: std.StringHashMap(MemoEntry),

    pub fn init(allocator: std.mem.Allocator) Memo {
        return .{ .allocator = allocator, .map = std.StringHashMap(MemoEntry).init(allocator) };
    }

    pub fn deinit(self: *Memo) void {
        var it = self.map.iterator();
        while (it.next()) |kv| {
            self.allocator.free(kv.key_ptr.*);
            freeFileContent(self.allocator, kv.value_ptr.fc);
        }
        self.map.deinit();
    }

    /// Drop entries for paths no longer present (deleted files).
    fn sweep(self: *Memo, live: *const std.StringHashMap(void)) void {
        var stale: std.ArrayList([]const u8) = .empty;
        defer stale.deinit(self.allocator);
        var it = self.map.iterator();
        while (it.next()) |kv| {
            if (!live.contains(kv.key_ptr.*)) {
                stale.append(self.allocator, kv.key_ptr.*) catch continue;
            }
        }
        for (stale.items) |key| {
            if (self.map.fetchRemove(key)) |kv| {
                self.allocator.free(kv.key);
                freeFileContent(self.allocator, kv.value.fc);
            }
        }
    }
};

const Self = @This();

allocator: std.mem.Allocator,
real_entries: std.ArrayList(JobEntry),
file_contents: std.ArrayList(FileContent),
lang_list: std.ArrayList(LangCount),
boilerplate_count: usize,
original_lines: u64,
condensed_lines: u64,
/// False when file_contents borrows from a Memo (which retains ownership).
owns_contents: bool,

pub fn compute(data: *const ReportData, cfg: *const Config, allocator: std.mem.Allocator, pool: ?*Pool, memo: ?*Memo) !Self {
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
    errdefer if (memo == null) freeFileContents(allocator, &file_contents);

    // Per-file condensing runs tree-sitter over every file by far the most
    // expensive part of the LLM report. With a memo only changed files are
    // recomputed; the initial (or memo-less) pass fans out across the pool.
    if (memo) |m| {
        try computeMemoized(m, real_entries.items, cfg.llm_max_lines, &file_contents, allocator, pool);
    } else if (pool) |p| {
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
        .owns_contents = memo == null,
    };
}

/// Resolve file contents through the memo: reuse entries whose mtime is
/// unchanged, recompute the rest (into the memo), then drop deleted paths.
/// All FileContents stay memo-owned; `out` only borrows them.
fn computeMemoized(
    memo: *Memo,
    entries: []const JobEntry,
    max_lines: u64,
    out: *std.ArrayList(FileContent),
    allocator: std.mem.Allocator,
    pool: ?*Pool,
) !void {
    // Recompute misses in parallel only when there are enough of them to pay
    // for the fan-out (the cold first pass); the steady state is 1-2 misses.
    var misses: std.ArrayList(usize) = .empty;
    defer misses.deinit(allocator);
    for (entries, 0..) |entry, i| {
        const hit = memo.map.get(entry.path);
        if (hit == null or hit.?.mtime != entry.mtime) try misses.append(allocator, i);
    }

    if (pool != null and misses.items.len > 64) {
        const slots = try allocator.alloc(?FileContent, misses.items.len);
        defer allocator.free(slots);
        @memset(slots, null);

        var wg = WaitGroup.init(pool.?.io);
        for (misses.items, slots) |i, *slot| {
            pool.?.spawn(&wg, condenseJob, .{ &entries[i], slot, max_lines, memo.allocator }) catch {};
        }
        wg.wait();

        for (misses.items, slots) |i, *slot| {
            const fc = slot.* orelse try condenseEntry(&entries[i], max_lines, memo.allocator);
            try memoPut(memo, &entries[i], fc);
        }
    } else {
        for (misses.items) |i| {
            const fc = try condenseEntry(&entries[i], max_lines, memo.allocator);
            try memoPut(memo, &entries[i], fc);
        }
    }

    var live = std.StringHashMap(void).init(allocator);
    defer live.deinit();
    try live.ensureTotalCapacity(@intCast(entries.len));
    for (entries) |entry| live.putAssumeCapacity(entry.path, {});
    memo.sweep(&live);

    try out.ensureTotalCapacity(allocator, entries.len);
    for (entries) |entry| {
        out.appendAssumeCapacity(memo.map.get(entry.path).?.fc);
    }
}

/// Insert or replace a memo entry, freeing any superseded content.
fn memoPut(memo: *Memo, entry: *const JobEntry, fc: FileContent) !void {
    const gop = try memo.map.getOrPut(entry.path);
    if (gop.found_existing) {
        freeFileContent(memo.allocator, gop.value_ptr.fc);
    } else {
        // The live entry's path is freed whenever the file changes; the memo
        // outlives that, so it owns a copy.
        gop.key_ptr.* = try memo.allocator.dupe(u8, entry.path);
    }
    gop.value_ptr.* = .{ .mtime = entry.mtime, .fc = fc };
}

pub fn deinit(self: *Self) void {
    if (self.owns_contents) {
        freeFileContents(self.allocator, &self.file_contents);
    } else {
        self.file_contents.deinit(self.allocator);
    }
    self.real_entries.deinit(self.allocator);
    self.lang_list.deinit(self.allocator);
}

/// Percentage of source lines dropped by condensing (0 when it grew or was empty).
pub fn reductionPct(self: *const Self) u64 {
    if (self.original_lines == 0 or self.condensed_lines > self.original_lines) return 0;
    return 100 * (self.original_lines - self.condensed_lines) / self.original_lines;
}

fn freeFileContent(allocator: std.mem.Allocator, fc: FileContent) void {
    switch (fc) {
        .condensed => |s| allocator.free(s),
        .ast => |chunks| allocator.free(chunks),
    }
}

fn freeFileContents(allocator: std.mem.Allocator, list: *std.ArrayList(FileContent)) void {
    for (list.items) |fc| freeFileContent(allocator, fc);
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
