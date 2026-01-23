const std = @import("std");

pub const ProcessStats = struct {
    cached_files: std.atomic.Value(usize),
    processed_files: std.atomic.Value(usize),
    ignored_files: std.atomic.Value(usize),

    pub fn init() ProcessStats {
        return .{
            .cached_files = std.atomic.Value(usize).init(0),
            .processed_files = std.atomic.Value(usize).init(0),
            .ignored_files = std.atomic.Value(usize).init(0),
        };
    }

    pub fn printSummary(self: *const ProcessStats) void {
        const cached = self.cached_files.load(.monotonic);
        const processed = self.processed_files.load(.monotonic);
        const ignored = self.ignored_files.load(.monotonic);
        const total = cached + processed + ignored;

        std.log.info("=== Processing Summary ===", .{});
        std.log.info("Total files: {d}", .{total});
        std.log.info("Cached (from .cache): {d}", .{cached});
        std.log.info("Processed (updated): {d}", .{processed});
        std.log.info("Ignored: {d}", .{ignored});
    }
};
