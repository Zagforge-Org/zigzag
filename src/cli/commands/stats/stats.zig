const std = @import("std");

/// ProcessStats processes statistics about the files processed by the runner.
pub const ProcessStats = struct {
    cached_files: std.atomic.Value(usize),
    processed_files: std.atomic.Value(usize),
    ignored_files: std.atomic.Value(usize),
    binary_files: std.atomic.Value(usize),

    pub fn init() ProcessStats {
        return .{
            .cached_files = std.atomic.Value(usize).init(0),
            .processed_files = std.atomic.Value(usize).init(0),
            .ignored_files = std.atomic.Value(usize).init(0),
            .binary_files = std.atomic.Value(usize).init(0),
        };
    }

    pub fn printSummary(self: *const ProcessStats) void {
        const cached = self.cached_files.load(.monotonic);
        const processed = self.processed_files.load(.monotonic);
        const ignored = self.ignored_files.load(.monotonic);
        const binary = self.binary_files.load(.monotonic);
        const source = cached + processed;
        const total = source + ignored + binary;

        std.log.info("=== Processing Summary ===", .{});
        std.log.info("Total files: {d}", .{total});
        std.log.info("Source files: {d} (cached: {d}, updated: {d})", .{ source, cached, processed });
        std.log.info("Binary files: {d}", .{binary});
        std.log.info("Ignored: {d}", .{ignored});
    }
};
