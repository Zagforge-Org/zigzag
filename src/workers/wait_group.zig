const std = @import("std");
const rt = @import("../runtime.zig");

pub const WaitGroup = struct {
    mutex: std.Io.Mutex = .init,
    cond: std.Io.Condition = .init,
    counter: usize = 0,

    const Self = @This();

    pub fn init() Self {
        return Self{};
    }

    /// Increment the counter by one safely.
    pub fn start(self: *Self) void {
        self.mutex.lockUncancelable(rt.io());
        defer self.mutex.unlock(rt.io());
        self.counter += 1;
    }

    pub fn finish(self: *Self) void {
        self.mutex.lockUncancelable(rt.io());
        defer self.mutex.unlock(rt.io());
        if (self.counter == 0) return;
        self.counter -= 1;
        // If no active jobs left, wake up any threads waiting on `wait()`
        if (self.counter == 0) {
            self.cond.broadcast(rt.io());
        }
    }

    // Wait for all active jobs to finish.
    pub fn wait(self: *Self) void {
        self.mutex.lockUncancelable(rt.io());
        defer self.mutex.unlock(rt.io());
        while (self.counter != 0) {
            self.cond.waitUncancelable(rt.io(), &self.mutex);
        }
    }

    // Check if all active jobs have finished without blocking.
    pub fn isDone(self: *Self) bool {
        self.mutex.lockUncancelable(rt.io());
        defer self.mutex.unlock(rt.io());
        return self.counter == 0;
    }
};
