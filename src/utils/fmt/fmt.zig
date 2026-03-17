const std = @import("std");

/// fmtBytes formats a byte count into a human-readable string.
/// Writes into buf and returns a slice — caller must not overwrite buf before consuming the result.
/// html=true appends " (w/ content)" to indicate an HTML content sidecar is included.
/// n == 0 returns "—" (em dash, a static string literal — no buf write).
pub fn fmtBytes(buf: []u8, n: u64, html: bool) []const u8 {
    if (n == 0) return "—";
    const mb = @as(f64, @floatFromInt(n)) / (1024.0 * 1024.0);
    const kb = @as(f64, @floatFromInt(n)) / 1024.0;
    const suffix: []const u8 = if (html) " (w/ content)" else "";
    if (n >= 1024 * 1024)
        return std.fmt.bufPrint(buf, "{d:.1} MB{s}", .{ mb, suffix }) catch "?";
    if (n >= 1024)
        return std.fmt.bufPrint(buf, "{d:.1} KB{s}", .{ kb, suffix }) catch "?";
    return std.fmt.bufPrint(buf, "{d} B{s}", .{ n, suffix }) catch "?";
}

/// fmtElapsed formats a nanosecond duration into a human-readable string.
/// Writes into buf and returns a slice into buf.
/// ns < 1_000_000        → "< 1ms"
/// ns < 1_000_000_000    → "{d}ms"       (e.g. "42ms")
/// ns >= 1_000_000_000   → "{d}.{d:0>2}s" (e.g. "1.50s")
pub fn fmtElapsed(ns: u64, buf: []u8) []const u8 {
    if (ns < 1_000_000) {
        return std.fmt.bufPrint(buf, "< 1ms", .{}) catch buf[0..0];
    } else if (ns < 1_000_000_000) {
        const ms = ns / 1_000_000;
        return std.fmt.bufPrint(buf, "{d}ms", .{ms}) catch buf[0..0];
    } else {
        const secs = ns / 1_000_000_000;
        const frac = (ns % 1_000_000_000) / 10_000_000;
        return std.fmt.bufPrint(buf, "{d}.{d:0>2}s", .{ secs, frac }) catch buf[0..0];
    }
}
