const std = @import("std");

const KB: u64 = 1024;
const MB: u64 = KB * 1024;

const ns_per_ms = std.time.ns_per_ms;
const ns_per_s = std.time.ns_per_s;

/// Formats a byte count into a human-readable string.
///
/// Writes into `buf` and returns a slice backed by it.
/// The returned slice is valid until `buf` is reused.
///
/// Examples:
/// - "—"
/// - "512 B"
/// - "1.5 KB"
/// - "12.8 MB"
///
/// When `html` is true, appends " (w/ content)".
pub fn fmtBytes(buf: []u8, bytes: u64, html: bool) []const u8 {
    if (bytes == 0)
        return "—";

    const suffix = if (html) " (w/ content)" else "";

    if (bytes < KB)
        return std.fmt.bufPrint(buf, "{d} B{s}", .{
            bytes,
            suffix,
        }) catch "?";

    var value: f64 = @floatFromInt(bytes);
    var unit: []const u8 = "KB";

    if (bytes >= MB) {
        value /= MB;
        unit = "MB";
    } else {
        value /= KB;
    }

    return std.fmt.bufPrint(buf, "{d:.1} {s}{s}", .{
        value,
        unit,
        suffix,
    }) catch "?";
}

/// Formats a duration in milliseconds.
///
/// Examples:
/// - "< 1 ms"
/// - "42 ms"
pub fn fmtMilliseconds(buf: []u8, ns: u64) []const u8 {
    const ms = ns / ns_per_ms;

    if (ms == 0)
        return "< 1 ms";

    return std.fmt.bufPrint(buf, "{d} ms", .{ms}) catch "?";
}

/// Formats an integer with thousands separators.
///
/// Example:
/// 1234567 -> "1,234,567"
pub fn fmtThousands(buf: []u8, value: usize) []const u8 {
    var tmp: [32]u8 = undefined;
    const digits = std.fmt.bufPrint(&tmp, "{d}", .{value}) catch return "?";

    var out: usize = 0;

    for (digits, 0..) |c, i| {
        if (i != 0 and (digits.len - i) % 3 == 0) {
            if (out >= buf.len)
                return buf[0..out];

            buf[out] = ',';
            out += 1;
        }

        if (out >= buf.len)
            return buf[0..out];

        buf[out] = c;
        out += 1;
    }

    return buf[0..out];
}

/// Formats an elapsed duration.
///
/// Examples:
/// - "< 1ms"
/// - "42ms"
/// - "1.53s"
/// - "12.08s"
pub fn fmtElapsed(buf: []u8, ns: u64) []const u8 {
    if (ns < ns_per_ms)
        return "< 1ms";

    if (ns < ns_per_s) {
        const ms = ns / ns_per_ms;
        return std.fmt.bufPrint(buf, "{d}ms", .{ms}) catch "?";
    }

    const secs = ns / ns_per_s;
    const hundredths = (ns % ns_per_s) / (ns_per_s / 100);

    return std.fmt.bufPrint(buf, "{d}.{d:0>2}s", .{
        secs,
        hundredths,
    }) catch "?";
}
