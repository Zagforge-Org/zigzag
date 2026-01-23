const FileContext = @import("../context.zig").FileContext;

pub const TProcessWriter = fn (*FileContext, []const u8) anyerror!void;

/// processWriter processes the content of a file.
pub fn processWriter(ctx: *FileContext, content: []const u8) !void {
    ctx.md_mutex.lock();
    defer ctx.md_mutex.unlock();

    _ = try ctx.md.write(content);
}
