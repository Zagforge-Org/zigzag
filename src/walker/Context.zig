const std = @import("std");

const Pool = @import("../workers/pool.zig").Pool;
const WaitGroup = @import("../workers/wait_group.zig").WaitGroup;
const FileContext = @import("../cli/context.zig").FileContext;
const Cache = @import("../cache/Cache.zig");
const ProcessStats = @import("../cli/commands/stats.zig").ProcessStats;
const JobEntry = @import("../jobs/entry.zig").JobEntry;
const BinaryEntry = @import("../jobs/entry.zig").BinaryEntry;

pool: *Pool,
wg: *WaitGroup,
file_ctx: *FileContext,
cache: ?*Cache,
stats: *ProcessStats,
file_entries: *std.StringHashMap(JobEntry),
binary_entries: *std.StringHashMap(BinaryEntry),
entries_mutex: *std.Io.Mutex,
allocator: std.mem.Allocator,
dir_semaphore: std.Io.Semaphore = .{ .permits = 64 },
