const std = @import("std");

const FileContext = @import("../cli/context.zig").FileContext;
const CacheImpl = @import("../cache/impl.zig").CacheImpl;
const ProcessStats = @import("../cli/stats.zig").ProcessStats;
const JobEntry = @import("entry.zig").JobEntry;

pub const Job = struct {
    path: []const u8,
    file_ctx: ?*FileContext,
    cache: *CacheImpl,
    stats: *ProcessStats,
    file_entries: *std.StringHashMap(JobEntry),
    entries_mutex: *std.Thread.Mutex,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Job) void {
        self.allocator.free(self.path);
    }
};
