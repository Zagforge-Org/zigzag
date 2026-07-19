const std = @import("std");
const Walk = @import("../../../fs/Walk.zig");
const walkerCallback = @import("../../../walker/callback.zig").walkerCallback;
const Config = @import("../config/config.zig").Config;
const FileContext = @import("../../context.zig").FileContext;
const Pool = @import("../../../workers/Pool.zig");
const WaitGroup = @import("../../../workers/WaitGroup.zig");
const Cache = @import("../../../cache/Cache.zig");
const ProcessStats = @import("../stats.zig").ProcessStats;
const Job = @import("../../../jobs/Job.zig");
const JobEntry = @import("../../../jobs/entries.zig").JobEntry;
const BinaryEntry = @import("../../../jobs/entries.zig").BinaryEntry;
const Context = @import("../../../walker/Context.zig");
const report = @import("../report.zig");
const log = @import("../../../utils/logger/Logger.zig");

/// Per-path persistent state for watch mode.
/// Heap-allocated so that entries_mutex has a stable address for thread pool jobs.
pub const State = struct {
    io: std.Io,
    root_path: []const u8,
    md_path: []const u8,
    file_entries: std.StringHashMap(JobEntry),
    binary_entries: std.StringHashMap(BinaryEntry),
    entries_mutex: std.Io.Mutex,
    file_ctx: FileContext,
    allocator: std.mem.Allocator,

    /// Run initial full directory scan and return heap-allocated state.
    pub fn init(
        io: std.Io,
        stats: *ProcessStats,
        cfg: *const Config,
        cache: ?*Cache,
        path: []const u8,
        pool: *Pool,
        allocator: std.mem.Allocator,
    ) !*State {
        var dir = std.Io.Dir.cwd().openDir(io, path, .{}) catch return error.NotADirectory;
        dir.close(io);

        const output_filename: []const u8 = if (cfg.output) |o| o else "report.md";
        const md_path = try report.resolveOutputPath(io, allocator, cfg, path, output_filename);
        errdefer allocator.free(md_path);

        const self = try allocator.create(State);
        self.* = .{
            .root_path = try allocator.dupe(u8, path),
            .md_path = md_path,
            .file_entries = std.StringHashMap(JobEntry).init(allocator),
            .binary_entries = std.StringHashMap(BinaryEntry).init(allocator),
            .entries_mutex = .init,
            .io = io,
            .file_ctx = .{
                .io = io,
                .ignore_list = .empty,
                .md = undefined,
                .md_mutex = undefined,
            },
            .allocator = allocator,
        };

        try self.buildIgnoreList(cfg);

        var wg = WaitGroup.init(io);
        var walker_ctx = Context{
            .pool = pool,
            .wg = &wg,
            .file_ctx = &self.file_ctx,
            .cache = cache,
            .stats = stats,
            .file_entries = &self.file_entries,
            .binary_entries = &self.binary_entries,
            .entries_mutex = &self.entries_mutex,
            .allocator = allocator,
        };

        const walker = try Walk.init(io, allocator);
        const walk_ctx: ?*FileContext = @ptrCast(@alignCast(&walker_ctx));
        try walker.walkDir(path, walkerCallback, walk_ctx);
        wg.wait();

        const sv = stats.getSummary();
        log.summary(io, .{ .path = path, .total = sv.total, .source = sv.source, .cached = sv.cached, .fresh = sv.processed, .binary = sv.binary, .ignored = sv.ignored });

        return self;
    }

    fn buildIgnoreList(self: *State, cfg: *const Config) !void {
        const alloc = self.allocator;
        const base_output_dir: []const u8 = if (cfg.output_dir) |d| d else "zigzag-reports";
        try self.file_ctx.ignore_list.append(alloc, try alloc.dupe(u8, base_output_dir));
        try self.file_ctx.ignore_list.append(alloc, try alloc.dupe(u8, self.md_path));
        if (cfg.json_output) try self.file_ctx.ignore_list.append(alloc, try report.deriveJsonPath(alloc, self.md_path));
        if (cfg.html_output) {
            const html_ign = try report.deriveHtmlPath(alloc, self.md_path);
            try self.file_ctx.ignore_list.append(alloc, html_ign);
            const content_ign = try report.deriveContentPath(alloc, html_ign);
            try self.file_ctx.ignore_list.append(alloc, content_ign);
        }
        if (cfg.llm_report) {
            const llm_path = try report.deriveLlmPath(alloc, self.md_path);
            try self.file_ctx.ignore_list.append(alloc, llm_path);
            const base: []const u8 = if (std.mem.endsWith(u8, llm_path, ".md"))
                llm_path[0 .. llm_path.len - 3]
            else
                llm_path;
            const chunk_pattern = try std.mem.concat(alloc, u8, &.{ base, "-" });
            try self.file_ctx.ignore_list.append(alloc, chunk_pattern);
            const manifest_pattern = try std.mem.concat(alloc, u8, &.{ base, ".manifest.json" });
            try self.file_ctx.ignore_list.append(alloc, manifest_pattern);
        }
        for (cfg.ignore_patterns.items) |pattern| {
            try self.file_ctx.ignore_list.append(alloc, try alloc.dupe(u8, pattern));
        }
    }

    pub fn deinit(self: *State) void {
        const alloc = self.allocator;
        alloc.free(self.root_path);
        alloc.free(self.md_path);

        var it = self.file_entries.iterator();
        while (it.next()) |entry| freeJobEntry(entry.value_ptr.*, alloc);
        self.file_entries.deinit();

        var bit = self.binary_entries.iterator();
        while (bit.next()) |entry| freeBinaryEntry(entry.value_ptr.*, alloc);
        self.binary_entries.deinit();

        for (self.file_ctx.ignore_list.items) |item| alloc.free(item);
        self.file_ctx.ignore_list.deinit(alloc);

        alloc.destroy(self);
    }

    /// Re-scan the entire root path and rebuild in-memory entries from scratch.
    /// Called after an inotify queue overflow to recover from lost events.
    pub fn rescan(self: *State, cache: ?*Cache, pool: *Pool) !void {
        {
            self.entries_mutex.lockUncancelable(self.io);
            defer self.entries_mutex.unlock(self.io);
            var it = self.file_entries.iterator();
            while (it.next()) |entry| freeJobEntry(entry.value_ptr.*, self.allocator);
            self.file_entries.clearRetainingCapacity();
            var bit = self.binary_entries.iterator();
            while (bit.next()) |entry| freeBinaryEntry(entry.value_ptr.*, self.allocator);
            self.binary_entries.clearRetainingCapacity();
        }

        var wg = WaitGroup.init(self.io);
        var stats = ProcessStats.init();
        var walker_ctx = Context{
            .pool = pool,
            .wg = &wg,
            .file_ctx = &self.file_ctx,
            .cache = cache,
            .stats = &stats,
            .file_entries = &self.file_entries,
            .binary_entries = &self.binary_entries,
            .entries_mutex = &self.entries_mutex,
            .allocator = self.allocator,
        };

        const walker = try Walk.init(self.io, self.allocator);
        const walk_ctx: ?*FileContext = @ptrCast(@alignCast(&walker_ctx));
        try walker.walkDir(self.root_path, walkerCallback, walk_ctx);
        wg.wait();
    }

    /// Re-process a single changed file and update the in-memory map.
    pub fn updateFile(self: *State, file_path: []const u8, cache: ?*Cache, pool: *Pool) !void {
        self.removeFile(file_path);

        const path_copy = try self.allocator.dupe(u8, file_path);
        var stats = ProcessStats.init();
        const job = Job{
            .path = path_copy,
            .file_ctx = &self.file_ctx,
            .cache = cache,
            .stats = &stats,
            .file_entries = &self.file_entries,
            .binary_entries = &self.binary_entries,
            .entries_mutex = &self.entries_mutex,
            .allocator = self.allocator,
        };

        var wg = WaitGroup.init(self.io);
        try pool.spawn(&wg, Job.process, .{job});
        wg.wait();
    }

    /// Remove a deleted file's entry from the in-memory map.
    pub fn removeFile(self: *State, file_path: []const u8) void {
        self.entries_mutex.lockUncancelable(self.io);
        defer self.entries_mutex.unlock(self.io);
        if (self.file_entries.fetchRemove(file_path)) |kv| freeJobEntry(kv.value, self.allocator);
        if (self.binary_entries.fetchRemove(file_path)) |kv| freeBinaryEntry(kv.value, self.allocator);
    }
};

fn freeJobEntry(entry: JobEntry, allocator: std.mem.Allocator) void {
    allocator.free(entry.path);
    allocator.free(entry.content);
    allocator.free(entry.extension);
}

fn freeBinaryEntry(entry: BinaryEntry, allocator: std.mem.Allocator) void {
    allocator.free(entry.path);
    allocator.free(entry.extension);
}
