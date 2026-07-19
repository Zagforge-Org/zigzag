//! Progress displays as a progress UI loader in the terminal

const std = @import("std");
const fmt_utils = @import("../utils/fmt/fmt.zig");
const ProcessStats = @import("../cli/commands/stats/stats.zig").ProcessStats;

const SPINNERS = [_][]const u8{
    "⠋",
    "⠙",
    "⠹",
    "⠸",
    "⠼",
    "⠴",
    "⠦",
    "⠧",
    "⠇",
    "⠏",
};

const COLORS = struct {
    const blue = "\x1b[94m";
    const white = "\x1b[97m";
    const gray = "\x1b[90m";
    const reset = "\x1b[0m";
};

const SEPARATOR = COLORS.gray ++ "────────────────────────────────────" ++ COLORS.reset ++ "\n";

const SPINNER_PHASE = 10;
const BAR_WIDTH = 20;
const BAR_MAX_FILL = BAR_WIDTH - 1;

const UPDATE_INTERVAL_NS = 100 * std.time.ns_per_ms;

io: std.Io,
stats: *const ProcessStats,
done: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
thread: ?std.Thread = null,
is_tty: bool,
start_ns: i128 = 0,

const Self = @This();

pub fn init(io: std.Io, stats: *const ProcessStats) Self {
    return .{
        .io = io,
        .stats = stats,
        .is_tty = std.Io.File.stderr().isTty(io) catch false,
    };
}

fn elapsedNs(self: *const Self) u64 {
    const delta =
        std.Io.Timestamp.now(self.io, .real).nanoseconds - self.start_ns;

    return @intCast(@max(0, delta));
}

/// Spawn render thread if TTY.
pub fn start(self: *Self) !void {
    if (!self.is_tty)
        return;

    self.start_ns = std.Io.Timestamp.now(self.io, .real).nanoseconds;

    self.thread = try std.Thread.spawn(.{}, renderLoop, .{self});
}

/// Stop renderer and print final result.
pub fn stop(self: *Self) void {
    self.done.store(true, .release);

    if (self.thread) |thread| {
        thread.join();
        self.thread = null;
    }

    if (!self.is_tty)
        return;

    const summary = self.stats.getSummary();

    writeSuccessLine(
        self.io,
        summary.total,
        summary.cached,
        self.elapsedNs(),
    );

    std.Io.File.stderr().writeStreamingAll(self.io, SEPARATOR) catch {};
}

fn writeSuccessLine(
    io: std.Io,
    total: usize,
    cached: usize,
    elapsed_ns: u64,
) void {
    const file_word = if (total == 1) "file" else "files";

    var elapsed_buf: [32]u8 = undefined;
    const elapsed = fmt_utils.fmtElapsed(&elapsed_buf, elapsed_ns);

    var buf: [512]u8 = undefined;

    const line = std.fmt.bufPrint(
        &buf,
        "\r\x1B[2K{s}✓{s} Scanned {s}{d}{s} {s} {s}({d} cached) {s}{s}\n",
        .{
            COLORS.gray,
            COLORS.reset,
            COLORS.white,
            total,
            COLORS.reset,
            file_word,
            COLORS.gray,
            cached,
            elapsed,
            COLORS.reset,
        },
    ) catch return;

    std.Io.File.stderr().writeStreamingAll(io, line) catch {};
}

/// Rolling upper bound on total files: assumes ~1/3 more remain, and never
/// shrinks so the bar can't jump backwards when a later frame reads a lower count.
pub fn growEstimate(estimate: usize, total: usize) usize {
    return @max(estimate, total * 4 / 3);
}

/// Filled bar cells for `total` against `estimate`, capped at BAR_MAX_FILL so the
/// bar never reads as full before the scan finishes. estimate >= 1 avoids div-by-zero.
pub fn fillFor(total: usize, estimate: usize) usize {
    return @min(BAR_MAX_FILL, total * BAR_WIDTH / estimate);
}

fn buildProgressBar(buf: []u8, fill: usize) []const u8 {
    var pos: usize = 0;

    @memcpy(buf[pos .. pos + COLORS.blue.len], COLORS.blue);
    pos += COLORS.blue.len;

    var i: usize = 0;

    while (i < fill) : (i += 1) {
        @memcpy(buf[pos .. pos + "█".len], "█");
        pos += "█".len;
    }

    @memcpy(buf[pos .. pos + COLORS.reset.len], COLORS.reset);
    pos += COLORS.reset.len;

    @memcpy(buf[pos .. pos + COLORS.gray.len], COLORS.gray);
    pos += COLORS.gray.len;

    while (i < BAR_WIDTH) : (i += 1) {
        @memcpy(buf[pos .. pos + "░".len], "░");
        pos += "░".len;
    }

    @memcpy(buf[pos .. pos + COLORS.reset.len], COLORS.reset);
    pos += COLORS.reset.len;

    return buf[0..pos];
}

fn renderLoop(self: *Self) void {
    var frame: usize = 0;
    var estimate: usize = 1;

    const stderr = std.Io.File.stderr();

    while (!self.done.load(.acquire)) {
        const summary = self.stats.getSummary();

        var buf: [512]u8 = undefined;

        const line = if (frame < SPINNER_PHASE) blk: {
            break :blk std.fmt.bufPrint(
                &buf,
                "\r\x1B[2K{s} Scanning… {d} files",
                .{
                    SPINNERS[frame % SPINNERS.len],
                    summary.total,
                },
            ) catch "\r\x1B[2K...";
        } else blk: {
            estimate = growEstimate(estimate, summary.total);

            const fill = fillFor(summary.total, estimate);

            var bar_buf: [256]u8 = undefined;
            const bar = buildProgressBar(&bar_buf, fill);

            break :blk std.fmt.bufPrint(
                &buf,
                "\r\x1B[2K{s} {d} files ({d} cached)",
                .{
                    bar,
                    summary.total,
                    summary.cached,
                },
            ) catch "\r\x1B[2K...";
        };

        stderr.writeStreamingAll(self.io, line) catch {};

        frame += 1;

        std.Io.sleep(
            self.io,
            .fromNanoseconds(UPDATE_INTERVAL_NS),
            .awake,
        ) catch {};
    }
}
