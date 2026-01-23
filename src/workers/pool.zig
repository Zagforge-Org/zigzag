const std = @import("std");
const builtin = @import("builtin");
const WaitGroup = @import("wait_group.zig").WaitGroup;

pub const Pool = struct {
    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},
    run_queue: std.SinglyLinkedList = .{},
    is_running: bool = true,
    allocator: std.mem.Allocator = undefined,
    threads: []std.Thread = &[_]std.Thread{},
    ids: ?*std.AutoArrayHashMapUnmanaged(std.Thread.Id, void) = null,

    const Self = @This();

    pub const Options = struct {
        allocator: std.mem.Allocator,
        n_jobs: ?usize = null,
        track_ids: bool = false,
        stack_size: usize = 16 * 1024 * 1024, // 16MB stack for safety
    };

    pub fn init(self: *Self, options: Options) !void {
        self.* = .{
            .allocator = options.allocator,
            .mutex = .{},
            .cond = .{},
            .run_queue = .{},
            .is_running = true,
        };

        if (builtin.single_threaded) return;

        const thread_count = options.n_jobs orelse @max(1, std.Thread.getCpuCount() catch 1);

        if (options.track_ids) {
            self.ids = try options.allocator.create(std.AutoArrayHashMapUnmanaged(std.Thread.Id, void));
            self.ids.?.* = .{};
            try self.ids.?.ensureTotalCapacity(options.allocator, 1 + thread_count);
            self.ids.?.putAssumeCapacityNoClobber(std.Thread.getCurrentId(), {});
        }

        self.threads = try options.allocator.alloc(std.Thread, thread_count);
        var spawned: usize = 0;
        errdefer self.join(spawned);

        for (self.threads) |*thread| {
            thread.* = try std.Thread.spawn(.{ .stack_size = options.stack_size, .allocator = options.allocator }, worker, .{self});
            spawned += 1;
        }
    }

    pub fn deinit(self: *Self) void {
        self.join(self.threads.len);

        if (self.ids) |ids_map| {
            ids_map.deinit(self.allocator);
            self.allocator.destroy(ids_map);
        }
    }

    fn join(self: *Self, spawned: usize) void {
        if (builtin.single_threaded) return;

        self.mutex.lock();
        self.is_running = false;
        self.mutex.unlock();

        self.cond.broadcast();

        for (self.threads[0..spawned]) |thread| {
            thread.join();
        }

        if (self.threads.len > 0) {
            self.allocator.free(self.threads);
            self.threads = &.{};
        }
    }

    pub fn spawnWg(self: *Self, wg: *WaitGroup, comptime func: anytype, args: anytype) !void {
        wg.start();

        if (builtin.single_threaded) {
            if (@typeInfo(@TypeOf(@call(.auto, func, args))) == .error_union) {
                try @call(.auto, func, args);
            } else {
                @call(.auto, func, args);
            }
            wg.finish();
            return;
        }

        const Args = @TypeOf(args);

        const Closure = struct {
            arguments: Args,
            pool: *Self,
            runnable: Runnable = .{ .runFn = runFn },
            wait_group: *WaitGroup,

            fn runFn(runnable: *Runnable) void {
                const closure: *@This() = @fieldParentPtr("runnable", runnable);

                if (@typeInfo(@TypeOf(@call(.auto, func, closure.arguments))) == .error_union) {
                    @call(.auto, func, closure.arguments) catch |err| {
                        std.log.err("Job failed with error: {}", .{err});
                    };
                } else {
                    @call(.auto, func, closure.arguments);
                }

                closure.wait_group.finish();

                const pool = closure.pool;
                pool.mutex.lock();
                defer pool.mutex.unlock();
                pool.allocator.destroy(closure);
            }
        };

        self.mutex.lock();
        defer self.mutex.unlock();

        const closure = self.allocator.create(Closure) catch {
            self.mutex.unlock();
            defer self.mutex.lock();

            if (@typeInfo(@TypeOf(@call(.auto, func, args))) == .error_union) {
                try @call(.auto, func, args);
            } else {
                @call(.auto, func, args);
            }
            wg.finish();
            return;
        };

        closure.* = .{
            .arguments = args,
            .pool = self,
            .wait_group = wg,
            .runnable = .{ .runFn = Closure.runFn },
        };

        self.run_queue.prepend(&closure.runnable.node);
        self.cond.signal();
    }
};

const Runnable = struct {
    runFn: RunFnProto,
    node: std.SinglyLinkedList.Node = .{},
};

const RunFnProto = *const fn (*Runnable) void;

fn worker(pool: *Pool) void {
    pool.mutex.lock();
    defer pool.mutex.unlock();

    if (pool.ids) |ids_map| {
        const thread_id = std.Thread.getCurrentId();
        ids_map.putAssumeCapacityNoClobber(thread_id, {});
    }

    while (true) {
        while (pool.run_queue.popFirst()) |run_node| {
            pool.mutex.unlock();
            defer pool.mutex.lock();

            const runnable: *Runnable = @fieldParentPtr("node", run_node);
            runnable.runFn(runnable);
        }

        if (!pool.is_running) break;

        pool.cond.wait(&pool.mutex);
    }
}
