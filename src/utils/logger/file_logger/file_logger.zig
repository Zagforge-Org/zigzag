const std = @import("std");

/// Writes timestamped plain-text log entries to a file inside the output dir.
/// Created via Logger.init(); must be deinitialized with Logger.deinit().
pub const Logger = struct {
    file: std.fs.File,

    /// Opens (or creates) `<output_dir>/zigzag.log` in append mode.
    pub fn init(output_dir: []const u8, allocator: std.mem.Allocator) !Logger {
        std.fs.cwd().makePath(output_dir) catch {};
        const log_path = try std.fs.path.join(allocator, &.{ output_dir, "zigzag.log" });
        defer allocator.free(log_path);
        const f = try std.fs.cwd().createFile(log_path, .{ .truncate = false });
        try f.seekFromEnd(0);
        return .{ .file = f };
    }

    pub fn deinit(self: *Logger) void {
        self.file.close();
    }

    /// Writes a timestamped line to the log file.
    pub fn log(self: Logger, comptime fmt: []const u8, args: anytype) void {
        const ts_raw = std.time.timestamp();
        const ts: u64 = if (ts_raw > 0) @intCast(ts_raw) else 0;
        const es = std.time.epoch.EpochSeconds{ .secs = ts };
        const ed = es.getEpochDay();
        const yd = ed.calculateYearDay();
        const md = yd.calculateMonthDay();
        const ds = es.getDaySeconds();

        var buf: [2048]u8 = undefined;
        const msg = std.fmt.bufPrint(
            &buf,
            "[{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}] " ++ fmt ++ "\n",
            .{
                yd.year,
                md.month.numeric(),
                md.day_index + 1,
                ds.getHoursIntoDay(),
                ds.getMinutesIntoHour(),
                ds.getSecondsIntoMinute(),
            } ++ args,
        ) catch return;
        self.file.writeAll(msg) catch {};
    }
};
