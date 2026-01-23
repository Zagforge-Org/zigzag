const std = @import("std");

const Pool = @import("../workers/pool.zig").Pool;
const WaitGroup = @import("../workers/wait_group.zig").WaitGroup;
const FileContext = @import("../cli/context.zig").FileContext;
const CacheImpl = @import("../cache/impl.zig").CacheImpl;
const ProcessStats = @import("../cli/commands/stats.zig").ProcessStats;
const JobEntry = @import("../jobs/entry.zig").JobEntry;

pub const WalkerCtx = struct {
    pool: *Pool,
    wg: *WaitGroup,
    file_ctx: *FileContext,
    cache: *CacheImpl,
    stats: *ProcessStats,
    file_entries: *std.StringHashMap(JobEntry),
    entries_mutex: *std.Thread.Mutex,
    allocator: std.mem.Allocator,
};
