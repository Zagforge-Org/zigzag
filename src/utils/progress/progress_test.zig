const std = @import("std");
const ProcessStats = @import("../../cli/commands/stats/stats.zig").ProcessStats;
const ProgressBar = @import("./progress.zig").ProgressBar;

test "rolling estimate: total=0 → fill=0, no div-by-zero" {
    const estimate: usize = 1;
    const total: usize = 0;
    const fill = @min(19, total * 20 / estimate);
    try std.testing.expectEqual(@as(usize, 0), fill);
}

test "rolling estimate: small count stays below cap" {
    var estimate: usize = 1;
    const total: usize = 50;
    estimate = @max(estimate, total * 4 / 3); // 66
    const fill = @min(19, total * 20 / estimate); // min(19, 15) = 15
    try std.testing.expect(fill < 20);
}

test "rolling estimate: estimate only grows" {
    var estimate: usize = 1;
    const t1: usize = 100;
    estimate = @max(estimate, t1 * 4 / 3); // 133
    const after_t1 = estimate;
    const t2: usize = 50; // total drops — estimate must not shrink
    estimate = @max(estimate, t2 * 4 / 3); // max(133, 66) = 133
    try std.testing.expectEqual(after_t1, estimate);
}

test "rolling estimate: large counts — fill caps at 19" {
    var estimate: usize = 1;
    const total: usize = 100_000;
    estimate = @max(estimate, total * 4 / 3); // 133333
    const fill = @min(19, total * 20 / estimate);
    try std.testing.expect(fill <= 19);
    try std.testing.expect(fill > 0);
}

test "stop() before start() does not panic" {
    var stats = ProcessStats.init();
    var pb = ProgressBar{ .stats = &stats, .is_tty = false, .done = std.atomic.Value(bool).init(false), .thread = null };
    pb.stop();
}

test "stop() with thread=null (simulates failed start()) does not panic" {
    var stats = ProcessStats.init();
    var pb = ProgressBar{ .stats = &stats, .is_tty = false, .done = std.atomic.Value(bool).init(false), .thread = null };
    pb.stop();
}

test "non-TTY: start() leaves thread null" {
    var stats = ProcessStats.init();
    var pb = ProgressBar{ .stats = &stats, .is_tty = false, .done = std.atomic.Value(bool).init(false), .thread = null };
    try pb.start();
    try std.testing.expect(pb.thread == null);
    pb.stop();
}

test "non-TTY: start()+stop() cycle completes without spawning thread" {
    var stats = ProcessStats.init();
    _ = stats.processed_files.fetchAdd(42, .monotonic);
    var pb = ProgressBar{ .stats = &stats, .is_tty = false, .done = std.atomic.Value(bool).init(false), .thread = null };
    try pb.start();
    pb.stop();
    try std.testing.expect(pb.thread == null);
}
