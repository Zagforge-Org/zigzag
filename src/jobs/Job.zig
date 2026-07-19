const std = @import("std");

const FileContext = @import("../cli/context.zig").FileContext;
const Cache = @import("../cache/Cache.zig");
const ProcessStats = @import("../cli/commands/stats.zig").ProcessStats;
const JobEntry = @import("entry.zig").JobEntry;
const BinaryEntry = @import("entry.zig").BinaryEntry;

const Self = @This();

io: std.Io,
path: []const u8,
file_ctx: ?*FileContext,
cache: ?*Cache,
stats: *ProcessStats,
file_entries: *std.StringHashMap(JobEntry),
binary_entries: *std.StringHashMap(BinaryEntry),
entries_mutex: *std.Io.Mutex,
allocator: std.mem.Allocator,

pub fn deinit(self: *Self) void {
    self.allocator.free(self.path);
}
