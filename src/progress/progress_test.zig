const std = @import("std");
const ProcessStats = @import("../cli/commands/stats/stats.zig").ProcessStats;
const Progress = @import("./Progress.zig");

test "fillFor: total=0 → fill=0, no div-by-zero" {
    try std.testing.expectEqual(@as(usize, 0), Progress.fillFor(0, 1));
}

test "fillFor: small count stays below full width" {
    const estimate = Progress.growEstimate(1, 50); // 66
    try std.testing.expect(Progress.fillFor(50, estimate) < 20);
}

test "growEstimate: estimate only grows" {
    const after_t1 = Progress.growEstimate(1, 100); // 133
    // total drops to 50 — estimate must not shrink
    try std.testing.expectEqual(after_t1, Progress.growEstimate(after_t1, 50));
}

test "fillFor: large counts — fill caps below full width" {
    const estimate = Progress.growEstimate(1, 100_000);
    const fill = Progress.fillFor(100_000, estimate);
    try std.testing.expect(fill <= 19);
    try std.testing.expect(fill > 0);
}

test "stop() before start() does not panic" {
    var stats = ProcessStats.init();
    var pb = Progress{ .io = std.testing.io, .stats = &stats, .is_tty = false };
    pb.stop();
}

test "stop() with thread=null (simulates failed start()) does not panic" {
    var stats = ProcessStats.init();
    var pb = Progress{ .io = std.testing.io, .stats = &stats, .is_tty = false };
    pb.stop();
}

test "non-TTY: start() leaves thread null" {
    var stats = ProcessStats.init();
    var pb = Progress{ .io = std.testing.io, .stats = &stats, .is_tty = false };
    try pb.start();
    try std.testing.expect(pb.thread == null);
    pb.stop();
}

test "non-TTY: start()+stop() cycle completes without spawning thread" {
    var stats = ProcessStats.init();
    _ = stats.processed_files.fetchAdd(42, .monotonic);
    var pb = Progress{ .io = std.testing.io, .stats = &stats, .is_tty = false };
    try pb.start();
    pb.stop();
    try std.testing.expect(pb.thread == null);
}
