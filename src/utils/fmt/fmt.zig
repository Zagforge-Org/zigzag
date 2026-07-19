const std = @import("std");

/// Formats a byte count into a human-readable string.
/// Writes into `buf` and returns a slice backed by it.
/// Caller must consume the result before reusing `buf`.
///
/// `html` appends " (w/ content)" when an HTML content sidecar exists.
/// Returns "—" for zero bytes.
pub fn fmtBytes(buf: []u8, n: u64, html: bool) []const u8 {
    if (n == 0) return "—";

    const suffix: []const u8 = if (html) " (w/ content)" else "";

    const value: f64 = @floatFromInt(n);
    const fmt: []const u8, const size: f64 = if (n >= 1024 * 1024)
        .{ "MB", value / (1024 * 1024) }
    else if (n >= 1024)
        .{ "KB", value / 1024 }
    else
        return std.fmt.bufPrint(buf, "{d} B{s}", .{ n, suffix }) catch "?";

    return std.fmt.bufPrint(buf, "{d:.1} {s}{s}", .{ size, fmt, suffix }) catch "?";
}

/// Formats a nanosecond duration as "< 1 ms" or "{d} ms".
pub fn fmtDuration(buf: []u8, ns: u64) []const u8 {
    const ns_per_ms = std.time.ns_per_ms;
    const ms = ns / ns_per_ms;

    if (ms == 0) return "< 1 ms";

    return std.fmt.bufPrint(buf, "{d} ms", .{ms}) catch "? ms";
}

/// Formats an integer with thousands separators (e.g. 1234567 -> "1,234,567").
pub fn fmtThousands(buf: []u8, n: usize) []const u8 {
    var tmp: [32]u8 = undefined;
    const digits = std.fmt.bufPrint(&tmp, "{d}", .{n}) catch return "";

    var out: usize = 0;
    for (digits, 0..) |c, i| {
        if (i > 0 and (digits.len - i) % 3 == 0) {
            if (out >= buf.len) return buf[0..out];
            buf[out] = ',';
            out += 1;
        }

        if (out >= buf.len) return buf[0..out];
        buf[out] = c;
        out += 1;
    }

    return buf[0..out];
}

/// Formats a nanosecond duration into a human-readable string.
///
/// Writes into `buf` and returns a slice backed by it.
///
/// - `< 1ms`
/// - `{d}ms`
/// - `{d}.{d:0>2}s`
pub fn fmtElapsed(buf: []u8, ns: u64) []const u8 {
    if (ns < std.time.ns_per_ms)
        return "< 1ms";

    if (ns < std.time.ns_per_s) {
        const ms = ns / std.time.ns_per_ms;
        return std.fmt.bufPrint(buf, "{d}ms", .{ms}) catch "";
    }

    const secs = ns / std.time.ns_per_s;
    const hundredths = (ns % std.time.ns_per_s) / (std.time.ns_per_s / 100);

    return std.fmt.bufPrint(buf, "{d}.{d:0>2}s", .{ secs, hundredths }) catch "";
}
