const std = @import("std");
const fs = @import("../fs/file.zig");
const FileContext = @import("../cli/context.zig").FileContext;

const DEFAULT_FILE = "test.txt";
const DEFAULT_ITERATIONS = 5;

fn processChunk(_: *FileContext, _: []const u8) anyerror!void {}

fn sumBytes(data: []const u8) u64 {
    var sum: u64 = 0;
    for (data) |b| sum += @intCast(b);
    return sum;
}

pub const FileBenchmark = struct {
    allocator: std.mem.Allocator,
    file_path: []const u8,
    iterations: u32,

    total_alloc_time: u64,
    total_chunked_time: u64,
    total_mapped_time: u64,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        file_path: ?[]const u8,
        iterations: ?u32,
    ) Self {
        return .{
            .allocator = allocator,
            .file_path = file_path orelse DEFAULT_FILE,
            .iterations = iterations orelse DEFAULT_ITERATIONS,
            .total_alloc_time = 0,
            .total_chunked_time = 0,
            .total_mapped_time = 0,
        };
    }

    pub fn initDefault(allocator: std.mem.Allocator) Self {
        return Self.init(allocator, null, null);
    }

    pub fn run(self: *Self) !void {
        for (0..self.iterations) |i| {
            std.debug.print("\n=== Iteration {d} ===\n", .{i + 1});
            var timer = try std.time.Timer.start();

            // readFileAlloc
            timer.reset();
            const alloc_content = fs.readFileAlloc(self.allocator, self.file_path) catch |err| {
                std.debug.print("Error reading file: {s}\n", .{@errorName(err)});
                return;
            };
            const alloc_time = timer.read();
            self.total_alloc_time += alloc_time;
            _ = sumBytes(alloc_content);
            self.allocator.free(alloc_content);

            std.debug.print("readFileAlloc:   {d:.3}ms\n", .{@as(f64, @floatFromInt(alloc_time)) / std.time.ns_per_ms});

            // --- readFileChunked ---
            var dev_null = try std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only });
            defer dev_null.close();
            var mutex = std.Thread.Mutex{};
            var ctx = FileContext{
                .ignore_list = .empty,
                .md = &dev_null,
                .md_mutex = &mutex,
            };
            defer ctx.ignore_list.deinit(self.allocator);
            timer.reset();
            try fs.readFileChunked(self.file_path, processChunk, &ctx);
            const chunked_time = timer.read();
            self.total_chunked_time += chunked_time;

            std.debug.print("readFileChunked: {d:.3}ms\n", .{@as(f64, @floatFromInt(chunked_time)) / std.time.ns_per_ms});

            // readFileMapped
            timer.reset();
            var mapped = fs.readFileMapped(self.file_path) catch |err| {
                std.debug.print("Error memory-mapping file: {s}\n", .{@errorName(err)});
                return;
            };
            defer mapped.deinit();

            _ = sumBytes(mapped.data);
            const mapped_time = timer.read();
            self.total_mapped_time += mapped_time;

            std.debug.print("readFileMapped:  {d:.3}ms\n", .{@as(f64, @floatFromInt(mapped_time)) / std.time.ns_per_ms});
        }

        // Average compute
        const avg_alloc = self.total_alloc_time / @as(u64, self.iterations);
        const avg_chunked = self.total_chunked_time / @as(u64, self.iterations);
        const avg_mapped = self.total_mapped_time / @as(u64, self.iterations);

        const fastest = @min(@min(avg_alloc, avg_chunked), avg_mapped);

        std.debug.print("\n=== Average Performance over {d} iterations ===\n", .{self.iterations});
        std.debug.print("readFileAlloc:   {d:.3}ms\n", .{@as(f64, @floatFromInt(avg_alloc)) / std.time.ns_per_ms});
        std.debug.print("readFileChunked: {d:.3}ms\n", .{@as(f64, @floatFromInt(avg_chunked)) / std.time.ns_per_ms});
        std.debug.print("readFileMapped:  {d:.3}ms\n", .{@as(f64, @floatFromInt(avg_mapped)) / std.time.ns_per_ms});

        std.debug.print("\nSpeedup vs fastest:\n", .{});
        std.debug.print("readFileAlloc:   {d:.2}x\n", .{@as(f64, @floatFromInt(avg_alloc)) / @as(f64, @floatFromInt(fastest))});
        std.debug.print("readFileChunked: {d:.2}x\n", .{@as(f64, @floatFromInt(avg_chunked)) / @as(f64, @floatFromInt(fastest))});
        std.debug.print("readFileMapped:  {d:.2}x\n", .{@as(f64, @floatFromInt(avg_mapped)) / @as(f64, @floatFromInt(fastest))});
    }
};
