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

    pub const Summary = struct {
        total: usize,
        source: usize,
        cached: usize,
        processed: usize,
        binary: usize,
        ignored: usize,
    };

    pub fn printSummary(self: *const ProcessStats) void {
        const sv = self.getSummary();
        std.log.info("=== Processing Summary ===", .{});
        std.log.info("Total files: {d}", .{sv.total});
        std.log.info("Source files: {d} (cached: {d}, updated: {d})", .{ sv.source, sv.cached, sv.processed });
        std.log.info("Binary files: {d}", .{sv.binary});
        std.log.info("Ignored: {d}", .{sv.ignored});
    }

    pub fn getSummary(self: *const ProcessStats) Summary {
        const cached = self.cached_files.load(.monotonic);
        const processed = self.processed_files.load(.monotonic);
        const ignored = self.ignored_files.load(.monotonic);
        const binary = self.binary_files.load(.monotonic);
        const source = cached + processed;
        const total = source + ignored + binary;
        return .{
            .total = total,
            .source = source,
            .cached = cached,
            .processed = processed,
            .binary = binary,
            .ignored = ignored,
        };
    }
};
