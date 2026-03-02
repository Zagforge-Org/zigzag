const std = @import("std");

/// ProcessStats processes statistics about the files processed by the runner.
pub const ProcessStats = struct {
    cached_files: std.atomic.Value(usize),
    processed_files: std.atomic.Value(usize),
    ignored_files: std.atomic.Value(usize),
    binary_files: std.atomic.Value(usize),

    pub fn init() ProcessStats {
        return .{
            .cached_files = std.atomic.Value(usize).init(0),
            .processed_files = std.atomic.Value(usize).init(0),
            .ignored_files = std.atomic.Value(usize).init(0),
            .binary_files = std.atomic.Value(usize).init(0),
        };
    }

    pub fn printSummary(self: *const ProcessStats) void {
        const cached = self.cached_files.load(.monotonic);
        const processed = self.processed_files.load(.monotonic);
        const ignored = self.ignored_files.load(.monotonic);
        const binary = self.binary_files.load(.monotonic);
        const source = cached + processed;
        const total = source + ignored + binary;

        std.log.info("=== Processing Summary ===", .{});
        std.log.info("Total files: {d}", .{total});
        std.log.info("Source files: {d} (cached: {d}, updated: {d})", .{ source, cached, processed });
        std.log.info("Binary files: {d}", .{binary});
        std.log.info("Ignored: {d}", .{ignored});
    }
};

test "ProcessStats.init initializes all counters to zero" {
    const stats = ProcessStats.init();
    try std.testing.expectEqual(@as(usize, 0), stats.cached_files.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 0), stats.processed_files.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 0), stats.ignored_files.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 0), stats.binary_files.load(.monotonic));
}

test "ProcessStats.binary_files counter increments correctly" {
    var stats = ProcessStats.init();
    _ = stats.binary_files.fetchAdd(1, .monotonic);
    _ = stats.binary_files.fetchAdd(1, .monotonic);
    try std.testing.expectEqual(@as(usize, 2), stats.binary_files.load(.monotonic));
}

test "ProcessStats counters are independent" {
    var stats = ProcessStats.init();
    _ = stats.cached_files.fetchAdd(3, .monotonic);
    _ = stats.processed_files.fetchAdd(5, .monotonic);
    _ = stats.ignored_files.fetchAdd(2, .monotonic);
    _ = stats.binary_files.fetchAdd(1, .monotonic);
    try std.testing.expectEqual(@as(usize, 3), stats.cached_files.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 5), stats.processed_files.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 2), stats.ignored_files.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 1), stats.binary_files.load(.monotonic));
}
