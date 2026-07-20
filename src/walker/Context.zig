const std = @import("std");

const Pool = @import("../workers/Pool.zig");
const WaitGroup = @import("../workers/WaitGroup.zig");
const FileContext = @import("../cli/context.zig").FileContext;
const Cache = @import("../cache/Cache.zig");
const Stats = @import("../cli/commands/stats.zig").Stats;
const JobEntry = @import("../jobs/entries.zig").JobEntry;
const BinaryEntry = @import("../jobs/entries.zig").BinaryEntry;

pool: *Pool,
wg: *WaitGroup,
file_ctx: *FileContext,
cache: ?*Cache,
stats: *Stats,
file_entries: *std.StringHashMap(JobEntry),
binary_entries: *std.StringHashMap(BinaryEntry),
entries_mutex: *std.Io.Mutex,
allocator: std.mem.Allocator,
dir_semaphore: std.Io.Semaphore = .{ .permits = 64 },
