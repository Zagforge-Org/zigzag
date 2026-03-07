const WalkerCtx = @import("../walker/context.zig").WalkerCtx;
const FileContext = @import("../cli/context.zig").FileContext;
const Job = @import("../jobs/job.zig").Job;
const processFileJob = @import("../jobs/process.zig").processFileJob;

pub fn walkerCallback(ctx: ?*FileContext, path: []const u8) anyerror!void {
    if (ctx) |c| {
        const walker_ctx: *WalkerCtx = @ptrCast(@alignCast(c));
        const path_copy = try walker_ctx.allocator.dupe(u8, path);
        errdefer walker_ctx.allocator.free(path_copy);

        const job = Job{
            .path = path_copy,
            .file_ctx = walker_ctx.file_ctx,
            .cache = walker_ctx.cache,
            .stats = walker_ctx.stats,
            .file_entries = walker_ctx.file_entries,
            .binary_entries = walker_ctx.binary_entries,
            .entries_mutex = walker_ctx.entries_mutex,
            .allocator = walker_ctx.allocator,
            .thread_allocator = walker_ctx.allocator, // placeholder; Task 2.3 wires real arena
        };

        try walker_ctx.pool.spawnWg(walker_ctx.wg, processFileJob, .{job});
    }
}
