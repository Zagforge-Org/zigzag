//! Fixed-size worker pool. Each worker owns a per-job arena
//! exposed to jobs as JobContext.allocator; long-lived allocations use the
//! pool's base allocator instead.

const std = @import("std");
const builtin = @import("builtin");

const WaitGroup = @import("WaitGroup.zig");

const STACK_SIZE = 16 * 1024 * 1024; // 16MB stack for safety

/// Passed as the last argument to every job. `allocator` is the calling worker's
/// arena which is cheap and is reset after the job returns, so only for scratch.
pub const JobContext = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
};

io: std.Io = undefined,
mutex: std.Io.Mutex = .init,
cond: std.Io.Condition = .init,
run_queue: std.DoublyLinkedList = .{},
is_running: bool = true,
allocator: std.mem.Allocator = undefined,
threads: []std.Thread = &.{},

const Self = @This();

pub const Options = struct {
    allocator: std.mem.Allocator,
    n_jobs: ?usize = null,
    stack_size: usize = STACK_SIZE,
};

pub fn init(self: *Self, io: std.Io, options: Options) !void {
    self.* = .{ .io = io, .allocator = options.allocator };

    if (builtin.single_threaded) return;

    const count = options.n_jobs orelse @max(1, std.Thread.getCpuCount() catch 1);
    self.threads = try options.allocator.alloc(std.Thread, count);

    var spawned: usize = 0;
    errdefer {
        self.stop();
        for (self.threads[0..spawned]) |thread| thread.join();
        options.allocator.free(self.threads);
        self.threads = &.{};
    }

    for (self.threads) |*thread| {
        thread.* = try std.Thread.spawn(
            .{ .stack_size = options.stack_size, .allocator = options.allocator },
            worker,
            .{self},
        );
        spawned += 1;
    }
}

pub fn deinit(self: *Self) void {
    self.stop();
    for (self.threads) |thread| thread.join();
    self.allocator.free(self.threads);
    self.threads = &.{};
}

/// Signal all workers to drain the queue and exit.
fn stop(self: *Self) void {
    self.mutex.lockUncancelable(self.io);
    self.is_running = false;
    self.mutex.unlock(self.io);
    self.cond.broadcast(self.io);
}

/// Queue `func(args..., JobContext)` on the pool, tracked by `wg`. On a
/// single-threaded build
pub fn spawn(self: *Self, wg: *WaitGroup, comptime func: anytype, args: anytype) !void {
    wg.start();

    if (builtin.single_threaded) {
        defer wg.finish();
        return callJob(func, .{ .io = self.io, .allocator = self.allocator }, args);
    }

    const Closure = struct {
        pool: *Self,
        wg: *WaitGroup,
        args: @TypeOf(args),
        runnable: Runnable = .{ .runFn = runFn },

        fn runFn(runnable: *Runnable) void {
            const closure: *@This() = @fieldParentPtr("runnable", runnable);
            const pool = closure.pool;
            const wg_ptr = closure.wg;
            const ctx = JobContext{ .io = pool.io, .allocator = runnable.thread_allocator };

            callJob(func, ctx, closure.args) catch |err|
                std.log.err("job failed: {}", .{err});

            pool.allocator.destroy(closure);
            wg_ptr.finish();
        }
    };

    const closure = self.allocator.create(Closure) catch {
        defer wg.finish();
        return callJob(func, .{ .io = self.io, .allocator = self.allocator }, args);
    };
    closure.* = .{ .pool = self, .wg = wg, .args = args };

    self.mutex.lockUncancelable(self.io);
    self.run_queue.append(&closure.runnable.node);
    self.mutex.unlock(self.io);

    self.cond.signal(self.io);
}

/// Invoke a job with `ctx` appended to its args, propagating any error.
fn callJob(comptime func: anytype, ctx: JobContext, args: anytype) anyerror!void {
    const result = @call(.auto, func, args ++ .{ctx});
    if (@typeInfo(@TypeOf(result)) == .error_union) return result;
}

const Runnable = struct {
    runFn: *const fn (*Runnable) void,
    node: std.DoublyLinkedList.Node = .{},
    thread_allocator: std.mem.Allocator = undefined, // set by worker before each job
};

fn worker(pool: *Self) void {
    // Per-thread arena: bump-pointer allocation, reset between jobs: O(1), no syscall.
    var arena = std.heap.ArenaAllocator.init(pool.allocator);
    defer arena.deinit();

    pool.mutex.lockUncancelable(pool.io);
    defer pool.mutex.unlock(pool.io);

    while (true) {
        while (pool.run_queue.popFirst()) |node| {
            pool.mutex.unlock(pool.io);
            defer pool.mutex.lockUncancelable(pool.io);

            const runnable: *Runnable = @fieldParentPtr("node", node);
            runnable.thread_allocator = arena.allocator();
            runnable.runFn(runnable);
            _ = arena.reset(.retain_capacity);
        }

        if (!pool.is_running) break;

        pool.cond.waitUncancelable(pool.io, &pool.mutex);
    }
}
