const std = @import("std");
const Timer = std.time.Timer;
const lg = @import("../utils/logger.zig");

pub const Benchmark = struct {
    timer: Timer, // Monotonic timer
    iterations: u64, // Number of iterations to run
    accumulator: u64, // Prevent optimizer from removing code

    const Self = @This();

    /// Initializes a new benchmark with a monotonic timer.
    pub fn init() !Self {
        const timer = try Timer.start();

        return Self{
            .timer = timer,
            .iterations = 0,
            .accumulator = 0,
        };
    }

    /// Run benchmark function for specified number of iterations.
    /// `func` receives a pointer to the accumulator to prevent optimization.
    pub fn run(self: *Self, iterations: u64, func: fn (*u64) void) void {
        self.iterations = iterations;
        self.accumulator = 0;
        self.timer.reset();
        for (0..iterations) |_| func(&self.accumulator);
    }

    /// Returns total elapsed time in nanoseconds.
    pub fn totalNs(self: *Self) u64 {
        return self.timer.read();
    }

    /// Returns average time per iteration in nanoseconds.
    pub fn avgNs(self: *Self) u64 {
        if (self.iterations == 0) return 0;
        return self.totalNs() / self.iterations;
    }

    /// Print formatted report.
    pub fn report(self: *Self) void {
        const total = self.totalNs();
        const avg = self.avgNs();
        lg.printSuccess("Benchmark Results:", .{});
        lg.printSuccess("  Total: {} ns", .{total});
        lg.printSuccess("  Average per iteration: {} ns", .{avg});
        _ = self.accumulator; // prevent optimizer from eliding the loop
    }
};
