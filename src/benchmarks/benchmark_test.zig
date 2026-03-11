const std = @import("std");
const Benchmark = @import("./benchmark.zig").Benchmark;

fn increment(acc: *u64) void {
    acc.* += 1;
}

test "Benchmark measures time for simple loop" {
    var bench = try Benchmark.init();

    bench.run(1_000_000, increment);

    const total = bench.totalNs();
    try std.testing.expect(total > 0);

    const avg = bench.avgNs();
    try std.testing.expect(avg > 0);
    try std.testing.expect(avg <= total);

    try std.testing.expectEqual(@as(u64, 1_000_000), bench.accumulator);
}
