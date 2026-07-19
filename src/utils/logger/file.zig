//! FileLogger is a timestamped plain-text lines to `<output_dir>/zigzag.log`.
//! Owns its own module-level state; enabled via `initFile`, disabled otherwise.

const std = @import("std");

var handle: ?std.Io.File = null;
var pos: u64 = 0;

/// Opens (or creates) `<output_dir>/zigzag.log` in append mode and enables `file()`.
pub fn initFile(io: std.Io, output_dir: []const u8, allocator: std.mem.Allocator) !void {
    std.Io.Dir.cwd().createDirPath(io, output_dir) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return e,
    };
    const log_path = try std.fs.path.join(allocator, &.{ output_dir, "zigzag.log" });
    defer allocator.free(log_path);
    const f = try std.Io.Dir.cwd().createFile(io, log_path, .{ .truncate = false, .read = true });
    handle = f;
    pos = (try f.stat(io)).size;
}

pub fn deinitFile(io: std.Io) void {
    if (handle) |f| f.close(io);
    handle = null;
}

/// Whether file logging is currently enabled.
pub fn fileEnabled() bool {
    return handle != null;
}

fn timestamp(io: std.Io, buf: []u8) ?[]u8 {
    const raw = std.Io.Timestamp.now(io, .real).toSeconds();
    const secs: u64 = if (raw > 0) @intCast(raw) else 0;

    const epoch = std.time.epoch.EpochSeconds{ .secs = secs };
    const day = epoch.getEpochDay();
    const year_day = day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch.getDaySeconds();

    return std.fmt.bufPrint(
        buf,
        "[{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}] ",
        .{
            year_day.year,
            month_day.month.numeric(),
            month_day.day_index + 1,
            day_seconds.getHoursIntoDay(),
            day_seconds.getMinutesIntoHour(),
            day_seconds.getSecondsIntoMinute(),
        },
    ) catch null;
}

pub fn file(
    io: std.Io,
    comptime fmt_str: []const u8,
    args: anytype,
) void {
    const f = handle orelse return;

    var buf: [2048]u8 = undefined;
    var len: usize = 0;

    const prefix = timestamp(io, buf[0..]) orelse return;
    len += prefix.len;

    const msg = std.fmt.bufPrint(
        buf[len..],
        fmt_str ++ "\n",
        args,
    ) catch return;

    len += msg.len;

    f.writePositionalAll(io, buf[0..len], pos) catch return;
    pos += len;
}
