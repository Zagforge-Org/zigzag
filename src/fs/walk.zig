const std = @import("std");
const FileContext = @import("../cli/context.zig").FileContext;
const TProcessWriter = @import("../cli/commands/writer.zig").TProcessWriter;
const Context = @import("../walker/Context.zig");
const JobContext = @import("../workers/Pool.zig").JobContext;

pub const WalkError = error{
    NotADirectory,
};

/// Pool job: walk a directory subtree in parallel.
/// path ownership is transferred in; freed here on completion.
/// WaitGroup is balanced by the pool's Closure.runFn — do NOT call wg.finish().
fn walkSubtreeJob(
    _: JobContext,
    walk_self: Walk,
    path: []const u8,
    depth: usize,
    callback: TProcessWriter,
    ctx: ?*FileContext,
    walker_ctx: *Context,
) !void {
    defer walk_self.allocator.free(path);
    try Walk.walkParallelInternal(walk_self, path, depth, callback, ctx, walker_ctx);
}

pub const Walk = struct {
    io: std.Io,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(io: std.Io, allocator: std.mem.Allocator) !Self {
        return Self{
            .io = io,
            .allocator = allocator,
        };
    }

    pub fn walkDir(
        self: Self,
        path: []const u8,
        callback: TProcessWriter,
        ctx: ?*FileContext,
    ) !void {
        try self.walkDirInternal(path, callback, ctx);
    }

    /// Depth threshold: directories at depths < THRESHOLD are walked synchronously
    /// (in-line, reusing the current thread); at depths >= THRESHOLD, each subtree
    /// is spawned as a pool job so multiple threads walk in parallel.
    const WALK_DEPTH_THRESHOLD: usize = 3;

    /// Entry point for parallel directory walking.
    pub fn walkDirParallel(
        self: Self,
        path: []const u8,
        depth: usize,
        callback: TProcessWriter,
        ctx: ?*FileContext,
        walker_ctx: *Context,
    ) !void {
        try walkParallelInternal(self, path, depth, callback, ctx, walker_ctx);
    }

    fn walkParallelInternal(
        self: Self,
        path: []const u8,
        depth: usize,
        callback: TProcessWriter,
        ctx: ?*FileContext,
        walker_ctx: *Context,
    ) !void {
        walker_ctx.dir_semaphore.waitUncancelable(self.io); // cap the number of simultaneously open dirs
        var dir = std.Io.Dir.cwd().openDir(self.io, path, .{ .access_sub_paths = true, .iterate = true }) catch {
            walker_ctx.dir_semaphore.post(self.io);
            return;
        };
        defer {
            dir.close(self.io);
            walker_ctx.dir_semaphore.post(self.io);
        }

        var it = dir.iterate();
        while (try it.next(self.io)) |entry| {
            if (std.mem.eql(u8, entry.name, ".") or std.mem.eql(u8, entry.name, "..")) continue;

            const full_path = try std.fs.path.join(self.allocator, &.{ path, entry.name });

            switch (entry.kind) {
                .file => {
                    defer self.allocator.free(full_path);
                    try callback(ctx.?, full_path);
                },
                .directory => {
                    if (depth < WALK_DEPTH_THRESHOLD) {
                        defer self.allocator.free(full_path);
                        try walkParallelInternal(self, full_path, depth + 1, callback, ctx, walker_ctx);
                    } else {
                        // Ownership of full_path transfers to the spawned job.
                        const path_owned = full_path;
                        walker_ctx.pool.spawn(walker_ctx.wg, walkSubtreeJob, .{
                            self, path_owned, depth + 1, callback, ctx, walker_ctx,
                        }) catch {
                            // spawn ran inline on alloc failure; path freed by job; wg balanced.
                            // If the inline run failed, log and free path defensively.
                            self.allocator.free(path_owned);
                        };
                    }
                },
                else => self.allocator.free(full_path),
            }
        }
    }

    fn walkDirInternal(
        self: Self,
        path: []const u8,
        callback: TProcessWriter,
        ctx: ?*FileContext,
    ) !void {
        var dir = try std.Io.Dir.cwd().openDir(self.io, path, .{ .access_sub_paths = true, .iterate = true });
        defer dir.close(self.io);

        var it = dir.iterate();
        while (try it.next(self.io)) |entry| {
            if (std.mem.eql(u8, entry.name, ".") or
                std.mem.eql(u8, entry.name, ".."))
            {
                continue;
            }

            const full_path = try std.fs.path.join(self.allocator, &.{ path, entry.name });
            defer self.allocator.free(full_path);

            switch (entry.kind) {
                .file => try callback(ctx.?, full_path),
                .directory => {
                    try self.walkDirInternal(full_path, callback, ctx);
                },
                else => {},
            }
        }
    }
};
