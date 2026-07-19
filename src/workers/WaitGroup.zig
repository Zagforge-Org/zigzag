const std = @import("std");

io: std.Io,
mutex: std.Io.Mutex = .init,
cond: std.Io.Condition = .init,
counter: usize = 0,

const Self = @This();

pub fn init(io: std.Io) Self {
    return Self{ .io = io };
}

/// Increment counter by one safely.
pub fn start(self: *Self) void {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    self.counter += 1;
}

pub fn finish(self: *Self) void {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);

    if (self.counter == 0) return;

    std.debug.assert(self.counter > 0);
    self.counter -= 1;

    // If no active jobs left, wake up any threads waiting on `wait()`
    if (self.counter == 0)
        self.cond.broadcast(self.io);
}

/// Wait for all active jobs to finish.
pub fn wait(self: *Self) void {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);

    while (self.counter != 0)
        self.cond.waitUncancelable(self.io, &self.mutex);
}

/// Check if all active jobs have finished without blocking.
pub fn isDone(self: *Self) bool {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    return self.counter == 0;
}
