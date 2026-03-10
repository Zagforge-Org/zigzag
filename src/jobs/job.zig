const std = @import("std");

const FileContext = @import("../cli/context.zig").FileContext;
const CacheImpl = @import("../cache/impl.zig").CacheImpl;
const ProcessStats = @import("../cli/commands/stats.zig").ProcessStats;
const JobEntry = @import("entry.zig").JobEntry;
const BinaryEntry = @import("entry.zig").BinaryEntry;

pub const Job = struct {
    path: []const u8,
    file_ctx: ?*FileContext,
    cache: ?*CacheImpl,
    stats: *ProcessStats,
    file_entries: *std.StringHashMap(JobEntry),
    binary_entries: *std.StringHashMap(BinaryEntry),
    entries_mutex: *std.Thread.Mutex,
    allocator: std.mem.Allocator,
    thread_allocator: std.mem.Allocator, // per-thread arena; reset after each job

    pub fn deinit(self: *Job) void {
        self.allocator.free(self.path);
    }
};
