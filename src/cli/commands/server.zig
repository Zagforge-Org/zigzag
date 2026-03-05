const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;

/// SSE dev server for watch mode.
///
/// Architecture: single event-loop thread using poll() for I/O multiplexing —
/// no thread-per-client. Connected SSE clients are held in a flat registry;
/// broadcast() stores the new payload under a mutex and returns immediately.
/// The event loop picks it up on its next 100 ms tick and pushes to all clients.
///
/// Named SSE events:
///   event: report — soft report update (JSON payload)
///   event: reload — full page reload signal
pub const SseServer = struct {
    allocator: std.mem.Allocator,
    listener: std.net.Server,
    html_path: []const u8,
    bound_port: u16,

    // Shared state between the caller thread and the event loop.
    // All fields below are protected by mu.
    mu: std.Thread.Mutex = .{},
    pending_payload: ?[]u8 = null, // next "report" broadcast queued by broadcast()
    pending_reload: bool = false, // next "reload" event queued by broadcastReload()
    stopped: bool = false,

    // current_payload: last successfully broadcast report payload.
    // Sent immediately to new SSE clients so they see data on first connect.
    // Only accessed from the event loop thread — no lock needed.
    current_payload: ?[]u8 = null,

    pub fn init(port: u16, html_path: []const u8, allocator: std.mem.Allocator) !*SseServer {
        const self = try allocator.create(SseServer);
        errdefer allocator.destroy(self);
        const addr = try std.net.Address.parseIp("127.0.0.1", port);
        const listener = try addr.listen(.{ .reuse_address = true });
        // Dupe so the caller can free its copy whenever it likes.
        const owned_path = try allocator.dupe(u8, html_path);
        errdefer allocator.free(owned_path);
        self.* = .{
            .allocator = allocator,
            .listener = listener,
            .html_path = owned_path,
            .bound_port = port,
        };
        return self;
    }

    /// Spawn the event-loop thread and return immediately.
    pub fn start(self: *SseServer) !void {
        const t = try std.Thread.spawn(.{}, eventLoop, .{self});
        t.detach();
    }

    /// Queue a "report" SSE event. Returns immediately; the event loop delivers it.
    pub fn broadcast(self: *SseServer, payload: []const u8) void {
        const copy = self.allocator.dupe(u8, payload) catch return;
        self.mu.lock();
        defer self.mu.unlock();
        if (self.pending_payload) |old| self.allocator.free(old);
        self.pending_payload = copy;
    }

    /// Queue a "reload" SSE event (triggers location.reload() in the browser).
    pub fn broadcastReload(self: *SseServer) void {
        self.mu.lock();
        defer self.mu.unlock();
        self.pending_reload = true;
    }

    /// Open the dashboard URL in the system browser (fire-and-forget).
    pub fn openBrowser(self: *const SseServer) void {
        const url = std.fmt.allocPrint(
            self.allocator,
            "http://127.0.0.1:{d}",
            .{self.bound_port},
        ) catch return;
        const t = std.Thread.spawn(.{}, openBrowserThread, .{ self.allocator, url }) catch {
            self.allocator.free(url);
            return;
        };
        t.detach();
    }

    pub fn stop(self: *SseServer) void {
        self.mu.lock();
        defer self.mu.unlock();
        self.stopped = true;
    }

    pub fn deinit(self: *SseServer) void {
        self.listener.deinit();
        self.allocator.free(self.html_path);
        self.mu.lock();
        if (self.pending_payload) |p| self.allocator.free(p);
        self.mu.unlock();
        if (self.current_payload) |p| self.allocator.free(p);
        self.allocator.destroy(self);
    }

    // -------------------------------------------------------------------------
    // Event loop
    // -------------------------------------------------------------------------

    fn eventLoop(self: *SseServer) void {
        // Client registry: each entry is the raw stream for a connected SSE client.
        // Only accessed from this thread — no lock needed.
        var clients: std.ArrayList(std.net.Stream) = .empty;
        defer {
            for (clients.items) |c| c.close();
            clients.deinit(self.allocator);
        }

        var last_keepalive_ms = std.time.milliTimestamp();
        const KEEPALIVE_MS: i64 = 15_000;

        while (true) {
            // Check stop flag
            {
                self.mu.lock();
                const stopped = self.stopped;
                self.mu.unlock();
                if (stopped) break;
            }

            // poll() the listener socket for incoming connections (100 ms timeout).
            var pfd = [1]posix.pollfd{.{
                .fd = self.listener.stream.handle,
                .events = posix.POLL.IN,
                .revents = 0,
            }};
            _ = posix.poll(&pfd, 100) catch {};

            if (pfd[0].revents & posix.POLL.IN != 0) {
                if (self.listener.accept()) |conn| {
                    self.handleNewConn(conn, &clients);
                } else |_| {}
            }

            // Consume pending broadcasts (set by the caller thread).
            self.mu.lock();
            const payload = self.pending_payload;
            self.pending_payload = null;
            const reload = self.pending_reload;
            self.pending_reload = false;
            self.mu.unlock();

            if (payload) |p| {
                defer self.allocator.free(p);
                // Cache for late-joining clients.
                if (self.current_payload) |old| self.allocator.free(old);
                self.current_payload = self.allocator.dupe(u8, p) catch null;
                // Push named "report" event to all connected clients.
                writePartsToAll(&clients, &.{ "event: report\ndata: ", p, "\n\n" });
            }

            if (reload) {
                writePartsToAll(&clients, &.{"event: reload\ndata: {}\n\n"});
            }

            // Keepalive comments keep the connection alive through proxies/browsers.
            const now_ms = std.time.milliTimestamp();
            if (now_ms - last_keepalive_ms >= KEEPALIVE_MS) {
                writePartsToAll(&clients, &.{": keep-alive\n\n"});
                last_keepalive_ms = now_ms;
            }
        }
    }

    // -------------------------------------------------------------------------
    // Connection handling (called from event loop thread)
    // -------------------------------------------------------------------------

    fn handleNewConn(
        self: *SseServer,
        conn: std.net.Server.Connection,
        clients: *std.ArrayList(std.net.Stream),
    ) void {
        // Read HTTP request headers (blocking, but almost instant — browser sends
        // all headers in one segment immediately after connect).
        var buf: [4096]u8 = undefined;
        var total: usize = 0;
        while (total < buf.len - 1) {
            const n = conn.stream.read(buf[total..]) catch {
                conn.stream.close();
                return;
            };
            if (n == 0) {
                conn.stream.close();
                return;
            }
            total += n;
            if (std.mem.indexOf(u8, buf[0..total], "\r\n\r\n") != null) break;
            if (std.mem.indexOf(u8, buf[0..total], "\n\n") != null) break;
        }

        const line_end = std.mem.indexOf(u8, buf[0..total], "\r\n") orelse
            std.mem.indexOf(u8, buf[0..total], "\n") orelse {
            conn.stream.close();
            return;
        };
        const first_line = buf[0..line_end];
        if (!std.mem.startsWith(u8, first_line, "GET ")) {
            conn.stream.close();
            return;
        }
        const path_end = std.mem.indexOfPos(u8, first_line, 4, " ") orelse first_line.len;
        const req_path = first_line[4..path_end];

        if (std.mem.eql(u8, req_path, "/__events")) {
            self.upgradeSse(conn.stream, clients);
        } else {
            serveHtml(self.allocator, self.html_path, conn.stream);
        }
    }

    fn upgradeSse(
        self: *SseServer,
        stream: std.net.Stream,
        clients: *std.ArrayList(std.net.Stream),
    ) void {
        const headers =
            "HTTP/1.1 200 OK\r\n" ++
            "Content-Type: text/event-stream\r\n" ++
            "Cache-Control: no-cache\r\n" ++
            "Connection: keep-alive\r\n" ++
            "Access-Control-Allow-Origin: *\r\n" ++
            "\r\n" ++
            // Instruct the browser to reconnect every 3 s on disconnect.
            "retry: 3000\n\n";
        stream.writeAll(headers) catch {
            stream.close();
            return;
        };

        // Immediately push the last known report so new clients don't wait for
        // the next file-change event.
        if (self.current_payload) |p| {
            const ok = blk: {
                stream.writeAll("event: report\ndata: ") catch break :blk false;
                stream.writeAll(p) catch break :blk false;
                stream.writeAll("\n\n") catch break :blk false;
                break :blk true;
            };
            if (!ok) {
                stream.close();
                return;
            }
        }

        clients.append(self.allocator, stream) catch {
            stream.close();
            return;
        };
    }
};

// -------------------------------------------------------------------------
// Helpers (package-level, no self)
// -------------------------------------------------------------------------

/// Write multiple string parts to every live client.
/// Removes clients whose writes fail (disconnected).
fn writePartsToAll(clients: *std.ArrayList(std.net.Stream), parts: []const []const u8) void {
    var i: usize = 0;
    while (i < clients.items.len) {
        const alive = blk: {
            for (parts) |part| {
                clients.items[i].writeAll(part) catch break :blk false;
            }
            break :blk true;
        };
        if (!alive) {
            clients.items[i].close();
            _ = clients.swapRemove(i);
        } else {
            i += 1;
        }
    }
}

fn serveHtml(allocator: std.mem.Allocator, html_path: []const u8, stream: std.net.Stream) void {
    defer stream.close();
    const html = std.fs.cwd().readFileAlloc(allocator, html_path, 64 * 1024 * 1024) catch {
        stream.writeAll("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n") catch {};
        return;
    };
    defer allocator.free(html);
    var hdr_buf: [128]u8 = undefined;
    const hdr = std.fmt.bufPrint(
        &hdr_buf,
        "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {d}\r\n\r\n",
        .{html.len},
    ) catch return;
    stream.writeAll(hdr) catch return;
    stream.writeAll(html) catch return;
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
