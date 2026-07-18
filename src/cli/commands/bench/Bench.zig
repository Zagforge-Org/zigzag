//! The `bench` command: runs a benchmarked report generation and prints timings.

const std = @import("std");

const Config = @import("../config/config.zig").Config;
const Cache = @import("../../../cache/Cache.zig");
const runner = @import("../runner.zig");
const lg = @import("../../../utils/utils.zig");
const BenchResult = @import("BenchResult.zig");
const Table = @import("Table.zig");

const Self = @This();

const cache_dir = &.{ ".", ".cache" };

io: std.Io,
cfg: *const Config,
allocator: std.mem.Allocator,

pub fn init(io: std.Io, cfg: *const Config, allocator: std.mem.Allocator) Self {
    return .{ .io = io, .cfg = cfg, .allocator = allocator };
}

pub fn run(self: Self) !void {
    const cache_path = try std.fs.path.join(self.allocator, cache_dir);
    defer self.allocator.free(cache_path);

    lg.printStep("Loading cache...", .{});
    var cache = try Cache.init(self.allocator, self.io, cache_path, self.cfg.small_threshold);
    defer cache.deinit();
    if (cache.entryCount() > 0)
        lg.printSuccess("Cache: {d} entries", .{cache.entryCount()});

    var result: BenchResult = .{};
    try runner.exec(self.cfg, &cache, self.allocator, &result);
    Table.init(&result).print(self.io);
}
