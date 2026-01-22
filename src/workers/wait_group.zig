const std = @import("std");

pub const WaitGroup = struct {
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},
    counter: usize = 0,

    const Self = @This();

    pub fn init() Self {
        return Self{};
    }

    /// Increment the counter by one safely.
    pub fn start(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.counter += 1;
    }

    pub fn finish(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.counter == 0) return;
        self.counter -= 1;
        // If no active jobs left, wake up any threads waiting on `wait()`
        if (self.counter == 0) {
            self.cond.broadcast();
        }
    }

    // Wait for all active jobs to finish.
    pub fn wait(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        while (self.counter != 0) {
            self.cond.wait(&self.mutex);
        }
    }

    // Check if all active jobs have finished without blocking.
    pub fn isDone(self: *Self) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.counter == 0;
    }
};
