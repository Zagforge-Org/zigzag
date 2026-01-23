const std = @import("std");
const FileContext = @import("../cli/context.zig").FileContext;
const TProcessWriter = @import("../cli/writer.zig").TProcessWriter;

pub const WalkError = error{
    NotADictionary,
};

pub const Walk = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
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

    fn walkDirInternal(
        self: Self,
        path: []const u8,
        callback: TProcessWriter,
        ctx: ?*FileContext,
    ) !void {
        var dir = try std.fs.cwd().openDir(path, .{ .access_sub_paths = true, .iterate = true });
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
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
