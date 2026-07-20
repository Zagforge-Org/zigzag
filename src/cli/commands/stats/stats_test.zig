const std = @import("std");
const Stats = @import("./Stats.zig");

test "Stats.init initializes all counters to zero" {
    const stats = Stats.init();
    try std.testing.expectEqual(@as(usize, 0), stats.cached_files.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 0), stats.processed_files.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 0), stats.ignored_files.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 0), stats.binary_files.load(.monotonic));
}

test "Stats.binary_files counter increments correctly" {
    var stats = Stats.init();
    _ = stats.binary_files.fetchAdd(1, .monotonic);
    _ = stats.binary_files.fetchAdd(1, .monotonic);
    try std.testing.expectEqual(@as(usize, 2), stats.binary_files.load(.monotonic));
}

test "Stats counters are independent" {
    var stats = Stats.init();
    _ = stats.cached_files.fetchAdd(3, .monotonic);
    _ = stats.processed_files.fetchAdd(5, .monotonic);
    _ = stats.ignored_files.fetchAdd(2, .monotonic);
    _ = stats.binary_files.fetchAdd(1, .monotonic);
    try std.testing.expectEqual(@as(usize, 3), stats.cached_files.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 5), stats.processed_files.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 2), stats.ignored_files.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 1), stats.binary_files.load(.monotonic));
}
