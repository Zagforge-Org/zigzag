const std = @import("std");
const builtin = @import("builtin");
const log = @import("../../logger/Logger.zig");
const isPortListening = @import("./watch/port_listening.zig").isPortListening;

pub const ServeConfig = struct {
    root_dir: []const u8,
    port: u16 = 8787,
    open_browser: bool = false,
    default_page: []const u8 = "report.html",
    allocator: std.mem.Allocator,
};

pub fn deriveMimeType(path: []const u8) []const u8 {
    if (std.mem.endsWith(u8, path, ".html")) return "text/html; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".json")) return "application/json";
    if (std.mem.endsWith(u8, path, ".css")) return "text/css";
    if (std.mem.endsWith(u8, path, ".js")) return "application/javascript";
    if (std.mem.endsWith(u8, path, ".md")) return "text/markdown";
    return "application/octet-stream";
}

/// Returns false if the request path would escape the root dir.
pub fn isPathSafe(req_path: []const u8) bool {
    if (req_path.len > 0 and req_path[0] == '/') return false;
    if (std.mem.indexOf(u8, req_path, "..") != null) return false;
    return true;
}

pub fn execServe(io: std.Io, cfg: ServeConfig) !void {
    const max_port_attempts = 10;
    var port = cfg.port;
    var server: std.Io.net.Server = blk: {
        for (0..max_port_attempts) |i| {
            if (isPortListening(io, port)) {
                if (i == 0) {
                    log.warn(io, "Port {d} already in use, trying port {d}..{d}...", .{ port, port + 1, port + max_port_attempts - 1 });
                }
                if (i == max_port_attempts - 1) {
                    log.err(io, "Ports {d}..{d} are all occupied. Cannot start server.", .{ cfg.port, port });
                    return error.AddressInUse;
                }
                port += 1;
                continue;
            }
            const addr = try std.Io.net.IpAddress.parse("127.0.0.1", port);
            if (addr.listen(io, .{ .reuse_address = true })) |srv| {
                break :blk srv;
            } else |err| {
                // Bind still failed (race condition or other error); treat as occupied.
                if (err != error.AddressInUse) return err;
                if (i == 0) {
                    log.warn(io, "Port {d} already in use, trying port {d}..{d}...", .{ port, port + 1, port + max_port_attempts - 1 });
                }
                port += 1;
            }
        }
        log.err(io, "Ports {d}..{d} are all occupied. Cannot start server.", .{ cfg.port, port - 1 });
        return error.AddressInUse;
    };
    defer server.deinit(io);

    log.success(io, "Serving ZigZag report at \x1b[4mhttp://127.0.0.1:{d}\x1b[0m", .{port});
    log.step(io, "Root: {s}", .{cfg.root_dir});
    log.step(io, "Press Ctrl+C to stop.", .{});

    if (cfg.open_browser) {
        openBrowser(io, cfg.allocator, port);
    }

    while (true) {
        const conn = server.accept(io) catch continue;
        handleConn(io, conn, cfg) catch {};
    }
}

fn handleConn(io: std.Io, conn: std.Io.net.Stream, cfg: ServeConfig) !void {
    defer conn.close(io);

    var read_buf: [4096]u8 = undefined;
    var stream_reader = conn.reader(io, &read_buf);
    const reader = &stream_reader.interface;

    var write_buf: [64 * 1024]u8 = undefined;
    var stream_writer = conn.writer(io, &write_buf);
    const writer = &stream_writer.interface;

    // Ignore the remaining headers.
    const first_line_raw = reader.takeDelimiterInclusive('\n') catch return;
    const first_line = std.mem.trimEnd(u8, first_line_raw, "\r\n");
    if (!std.mem.startsWith(u8, first_line, "GET ")) return;
    const path_end = std.mem.indexOfPos(u8, first_line, 4, " ") orelse first_line.len;
    const req_path_raw = first_line[4..path_end];

    // Strip leading slash and query string
    var req_path: []const u8 = req_path_raw;
    if (req_path.len > 0 and req_path[0] == '/') req_path = req_path[1..];
    if (std.mem.indexOf(u8, req_path, "?")) |q| req_path = req_path[0..q];

    // Default to index
    if (req_path.len == 0) req_path = cfg.default_page;

    // Security: reject path traversal
    if (!isPathSafe(req_path)) {
        try writer.writeAll("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n");
        try writer.flush();
        return;
    }

    const file_path = try std.fs.path.join(cfg.allocator, &.{ cfg.root_dir, req_path });
    defer cfg.allocator.free(file_path);

    const file = std.Io.Dir.cwd().openFile(io, file_path, .{}) catch {
        try writer.writeAll("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n");
        try writer.flush();
        return;
    };
    defer file.close(io);

    const file_size = if (file.stat(io)) |st| st.size else |_| {
        try writer.writeAll("HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\n\r\n");
        try writer.flush();
        return;
    };

    const mime = deriveMimeType(req_path);
    var hdr_buf: [256]u8 = undefined;
    const hdr = try std.fmt.bufPrint(
        &hdr_buf,
        "HTTP/1.1 200 OK\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nCache-Control: no-cache\r\n\r\n",
        .{ mime, file_size },
    );
    try writer.writeAll(hdr);

    var io_buf: [64 * 1024]u8 = undefined;
    while (true) {
        const n = try file.readStreaming(io, &.{io_buf[0..]});
        if (n == 0) break;
        try writer.writeAll(io_buf[0..n]);
    }
    try writer.flush();
}

fn openBrowser(io: std.Io, allocator: std.mem.Allocator, port: u16) void {
    const url = std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{port}) catch return;
    const t = std.Thread.spawn(.{}, openBrowserThread, .{ io, allocator, url }) catch {
        allocator.free(url);
        return;
    };
    t.detach();
}

fn openBrowserThread(io: std.Io, allocator: std.mem.Allocator, url: []u8) void {
    defer allocator.free(url);
    const argv: []const []const u8 = switch (builtin.os.tag) {
        .macos => &.{ "open", url },
        .windows => &.{ "cmd", "/C", "start", "", url },
        else => &.{ "xdg-open", url },
    };
    const result = std.process.run(allocator, io, .{ .argv = argv }) catch return;
    allocator.free(result.stdout);
    allocator.free(result.stderr);
}
