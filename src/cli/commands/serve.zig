const std = @import("std");
const builtin = @import("builtin");
const lg = @import("logger.zig");

pub const ServeConfig = struct {
    root_dir: []const u8,
    port: u16 = 8787,
    open_browser: bool = false,
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

pub fn execServe(cfg: ServeConfig) !void {
    const addr = try std.net.Address.parseIp("127.0.0.1", cfg.port);
    var server = try addr.listen(.{ .reuse_address = true });
    defer server.deinit();

    lg.printSuccess("Serving ZigZag report at \x1b[4mhttp://127.0.0.1:{d}\x1b[0m", .{cfg.port});
    lg.printStep("Root: {s}", .{cfg.root_dir});
    lg.printStep("Press Ctrl+C to stop.", .{});

    if (cfg.open_browser) {
        openBrowser(cfg.allocator, cfg.port);
    }

    while (true) {
        const conn = server.accept() catch continue;
        handleConn(conn, cfg) catch {};
    }
}

fn handleConn(conn: std.net.Server.Connection, cfg: ServeConfig) !void {
    defer conn.stream.close();

    var buf: [4096]u8 = undefined;
    var total: usize = 0;
    while (total < buf.len - 1) {
        const n = try conn.stream.read(buf[total..]);
        if (n == 0) return;
        total += n;
        if (std.mem.indexOf(u8, buf[0..total], "\r\n\r\n") != null) break;
        if (std.mem.indexOf(u8, buf[0..total], "\n\n") != null) break;
    }

    const line_end = std.mem.indexOf(u8, buf[0..total], "\r\n") orelse
        std.mem.indexOf(u8, buf[0..total], "\n") orelse return;
    const first_line = buf[0..line_end];
    if (!std.mem.startsWith(u8, first_line, "GET ")) return;
    const path_end = std.mem.indexOfPos(u8, first_line, 4, " ") orelse first_line.len;
    const req_path_raw = first_line[4..path_end];

    // Strip leading slash and query string
    var req_path: []const u8 = req_path_raw;
    if (req_path.len > 0 and req_path[0] == '/') req_path = req_path[1..];
    if (std.mem.indexOf(u8, req_path, "?")) |q| req_path = req_path[0..q];

    // Default to index
    if (req_path.len == 0) req_path = "report.html";

    // Security: reject path traversal
    if (!isPathSafe(req_path)) {
        try conn.stream.writeAll("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n");
        return;
    }

    const file_path = try std.fs.path.join(cfg.allocator, &.{ cfg.root_dir, req_path });
    defer cfg.allocator.free(file_path);

    const file = std.fs.cwd().openFile(file_path, .{}) catch {
        try conn.stream.writeAll("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n");
        return;
    };
    defer file.close();

    const file_size = file.getEndPos() catch {
        try conn.stream.writeAll("HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\n\r\n");
        return;
    };

    const mime = deriveMimeType(req_path);
    var hdr_buf: [256]u8 = undefined;
    const hdr = try std.fmt.bufPrint(
        &hdr_buf,
        "HTTP/1.1 200 OK\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nCache-Control: no-cache\r\n\r\n",
        .{ mime, file_size },
    );
    try conn.stream.writeAll(hdr);

    var io_buf: [64 * 1024]u8 = undefined;
    while (true) {
        const n = try file.read(&io_buf);
        if (n == 0) break;
        try conn.stream.writeAll(io_buf[0..n]);
    }
}

fn openBrowser(allocator: std.mem.Allocator, port: u16) void {
    const url = std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{port}) catch return;
    const t = std.Thread.spawn(.{}, openBrowserThread, .{ allocator, url }) catch {
        allocator.free(url);
        return;
    };
    t.detach();
}

fn openBrowserThread(allocator: std.mem.Allocator, url: []u8) void {
    defer allocator.free(url);
    const argv: []const []const u8 = switch (builtin.os.tag) {
        .macos => &.{ "open", url },
        .windows => &.{ "cmd", "/C", "start", "", url },
        else => &.{ "xdg-open", url },
    };
    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    _ = child.spawnAndWait() catch {};
}
