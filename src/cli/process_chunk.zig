const Context = @import("../cli/context.zig").Context;

pub const TProcessChunk = fn (*Context, []const u8) anyerror!void;

pub fn processChunk(ctx: *Context, content: []const u8) !void {
    ctx.md_mutex.lock();
    defer ctx.md_mutex.unlock();

    _ = try ctx.md.write(content);
}
