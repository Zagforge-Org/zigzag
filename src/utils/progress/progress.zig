const std = @import("std");
const fmt_utils = @import("../fmt/fmt.zig");
const ProcessStats = @import("../../cli/commands/stats/stats.zig").ProcessStats;

pub const ProgressBar = struct {
    stats: *const ProcessStats,
    done: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    thread: ?std.Thread = null,
    is_tty: bool,
    start_ns: i128 = 0,

    const Self = @This();

    const spinners = [10][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };
    const sep = "\x1b[90m" ++ "─" ** 36 ++ "\x1b[0m\n";

    pub fn init(stats: *const ProcessStats) Self {
        return .{
            .stats = stats,
            .is_tty = std.posix.isatty(std.fs.File.stderr().handle),
        };
    }

    /// Spawn render thread if TTY. Safe to call unconditionally.
    pub fn start(self: *Self) !void {
        if (!self.is_tty) return;
        self.start_ns = std.time.nanoTimestamp();
        self.thread = try std.Thread.spawn(.{}, renderLoop, .{self});
    }

    /// Signal render thread to stop, join it, then write final success line.
    /// Safe to call before start(), after a failed start(), or on non-TTY.
    pub fn stop(self: *Self) void {
        self.done.store(true, .release);
        if (self.thread) |t| {
            t.join();
            self.thread = null;
        }
        if (!self.is_tty) return;
        const sv = self.stats.getSummary();
        const elapsed_ns: u64 = blk: {
            const delta = std.time.nanoTimestamp() - self.start_ns;
            break :blk @intCast(@max(0, delta));
        };
        writeSuccessLine(sv.total, sv.cached, elapsed_ns);
        std.fs.File.stderr().writeAll(sep) catch {};
    }

    fn writeSuccessLine(total: usize, cached: usize, elapsed_ns: u64) void {
        var elapsed_buf: [32]u8 = undefined;
        const elapsed = fmt_utils.fmtElapsed(elapsed_ns, &elapsed_buf);
        const file_word: []const u8 = if (total == 1) "file" else "files";
        var buf: [512]u8 = undefined;
        const line = std.fmt.bufPrint(
            &buf,
            "\r\x1B[2K\x1b[92m✓\x1b[0m Scanned \x1b[97m{d}\x1b[0m {s} \x1b[90m({d} cached)  {s}\x1b[0m\n",
            .{ total, file_word, cached, elapsed },
        ) catch return;
        std.fs.File.stderr().writeAll(line) catch {};
    }

    fn renderLoop(pb: *Self) void {
        var frame: usize = 0;
        var estimate: usize = 1; // starts at 1 to prevent div-by-zero when total=0
        const stderr = std.fs.File.stderr();

        while (!pb.done.load(.acquire)) {
            const sv = pb.stats.getSummary();
            const total = sv.total;
            const cached = sv.cached;
            var buf: [512]u8 = undefined;

            if (frame < 10) {
                // Phase 1: spinner + counter (first ~1 second)
                const spinner = spinners[frame % 10];
                const line = std.fmt.bufPrint(&buf, "\r\x1B[2K{s} Scanning… {d} files", .{ spinner, total }) catch "\r\x1B[2K...";
                stderr.writeAll(line) catch {};
            } else {
                // Phase 2: rolling-estimate bar + counter (blue fill, dim empty, no brackets)
                estimate = @max(estimate, total * 4 / 3);
                const fill = @min(19, total * 20 / estimate); // cap at 95%

                var bar: [256]u8 = undefined;
                var bp: usize = 0;

                // Blue fill characters
                const blue_on = "\x1b[94m";
                const blue_off = "\x1b[0m";
                const dim_on = "\x1b[90m";
                const dim_off = "\x1b[0m";
                @memcpy(bar[bp .. bp + blue_on.len], blue_on);
                bp += blue_on.len;
                var i: usize = 0;
                while (i < fill) : (i += 1) {
                    @memcpy(bar[bp .. bp + "█".len], "█");
                    bp += "█".len;
                }
                @memcpy(bar[bp .. bp + blue_off.len], blue_off);
                bp += blue_off.len;

                // Dim empty characters
                @memcpy(bar[bp .. bp + dim_on.len], dim_on);
                bp += dim_on.len;
                while (i < 20) : (i += 1) {
                    @memcpy(bar[bp .. bp + "░".len], "░");
                    bp += "░".len;
                }
                @memcpy(bar[bp .. bp + dim_off.len], dim_off);
                bp += dim_off.len;

                const line = std.fmt.bufPrint(&buf, "\r\x1B[2K{s} {d} files ({d} cached)", .{ bar[0..bp], total, cached }) catch "\r\x1B[2K...";
                stderr.writeAll(line) catch {};
            }

            frame += 1;
            std.Thread.sleep(100 * std.time.ns_per_ms);
        }
    }
};
