const std = @import("std");
const builtin = @import("builtin");

// ---------------------------------------------------------------------------
// Windows socket I/O helpers
//
// This section provides helper utilities for performing socket input/output
// operations on Windows systems. It defines and exposes the necessary Winsock2
// external functions so they can be used directly where needed.
//
// The inner structures and functions are conditionally compiled only when
// targeting Windows, keeping the code portable while allowing platform-specific
// implementations.
//
// These externs are used by both socketRecv and gracefulClose, providing a
// consistent interface to interact with Windows sockets.
// ---------------------------------------------------------------------------

/// Winsock2 externs used in both socketRecv and gracefulClose on Windows.
//
/// The inner struct is only compiled when targeting Windows.
const win_ws2 = struct {
    extern "ws2_32" fn recv(s: std.posix.socket_t, buf: [*]u8, len: c_int, flags: c_int) callconv(.winapi) c_int;
    extern "ws2_32" fn shutdown(s: std.posix.socket_t, how: c_int) callconv(.winapi) c_int;
};

/// Read from a socket, bypassing ReadFile() on Windows.
/// Drop-in for Stream.read(): returns bytes read, 0 on EOF, or an error.
fn socketRecv(handle: std.posix.socket_t, buf: []u8) std.net.Stream.ReadError!usize {
    if (comptime builtin.os.tag == .windows) {
        if (buf.len == 0) return 0;
        const n = win_ws2.recv(handle, buf.ptr, @intCast(buf.len), 0);
        if (n < 0) return error.ConnectionResetByPeer;
        return @intCast(n);
    }
    return std.posix.read(handle, buf);
}

/// Gracefully close a TCP connection to avoid RST on Windows.
/// Without shutdown(SD_SEND) + drain, closesocket() sends RST if there is
/// any unread data in the receive buffer — the browser sees ERR_CONNECTION_RESET.
fn gracefulClose(stream: std.net.Stream) void {
    if (comptime builtin.os.tag == .windows) {
        _ = win_ws2.shutdown(stream.handle, 1); // SD_SEND = 1 → sends FIN
        // Drain remaining receive-buffer data so closesocket() does not RST.
        var drain: [1024]u8 = undefined;
        const drain_ptr: [*]u8 = @ptrCast(&drain);
        var drained: usize = 0;
        while (drained < 64 * 1024) {
            const n = win_ws2.recv(stream.handle, drain_ptr, @intCast(drain.len), 0);
            if (n <= 0) break; // 0 = peer closed, negative = error (e.g. WSAECONNRESET)
            drained += @intCast(n);
        }
    }
    stream.close();
}

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
    root_dir: []const u8, // directory to serve static files from
    default_page: []const u8, // filename returned for GET /
    bound_port: u16,

    // Shared state between the caller thread and the event loop.
    // All fields below are protected by mutex.
    mu: std.Thread.Mutex = .{},
    pending_payload: ?[]u8 = null, // next "report" broadcast queued by broadcast()
    pending_combined: ?[]u8 = null, // next "combined_update" broadcast queued by broadcastCombined()
    pending_reload: bool = false, // next "reload" event queued by broadcastReload()
    stopped: bool = false,

    // current_payload: last successfully broadcast report payload.
    // Sent immediately to new SSE clients so they see data on first connect.
    // Only accessed from the event loop thread — no lock needed.
    current_payload: ?[]u8 = null,
    // current_combined: last successfully broadcast combined_update payload.
    // Sent immediately to new SSE clients so they see combined data on first connect.
    // Only accessed from the event loop thread — no lock needed.
    current_combined: ?[]u8 = null,

    accept_thread: ?std.Thread = null,
    accept_queue: std.ArrayList(std.net.Server.Connection),
    accept_mu: std.Thread.Mutex = .{},

    pub fn init(port: u16, root_dir: []const u8, default_page: []const u8, allocator: std.mem.Allocator) !*SseServer {
        const self = try allocator.create(SseServer);
        errdefer allocator.destroy(self);

        const addr = try std.net.Address.parseIp("127.0.0.1", port);
        const listener = try addr.listen(.{ .reuse_address = true });

        const owned_dir = try allocator.dupe(u8, root_dir);
        errdefer allocator.free(owned_dir);

        const owned_page = try allocator.dupe(u8, default_page);
        errdefer allocator.free(owned_page);

        self.* = .{
            .allocator = allocator,
            .listener = listener,
            .root_dir = owned_dir,
            .default_page = owned_page,
            .bound_port = port,
            .accept_queue = .empty,
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

    /// Queue a "combined_update" SSE event. Returns immediately; the event loop delivers it.
    pub fn broadcastCombined(self: *SseServer, payload: []const u8) void {
        const copy = self.allocator.dupe(u8, payload) catch return;

        self.mu.lock();
        defer self.mu.unlock();

        if (self.pending_combined) |old| self.allocator.free(old);
        self.pending_combined = copy;
    }

    /// Queue a "reload" SSE event (triggers location.reload() in the browser).
    pub fn broadcastReload(self: *SseServer) void {
        self.mu.lock();
        self.pending_reload = true;
        self.mu.unlock();
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
        self.stopped = true;
        self.mu.unlock();
    }

    pub fn deinit(self: *SseServer) void {
        {
            self.mu.lock();
            defer self.mu.unlock();
            self.stopped = true;
        }

        self.listener.deinit();

        if (self.accept_thread) |t| t.join();

        {
            self.accept_mu.lock();
            defer self.accept_mu.unlock();

            for (self.accept_queue.items) |conn|
                conn.stream.close();

            self.accept_queue.deinit(self.allocator);
        }

        self.allocator.free(self.root_dir);
        self.allocator.free(self.default_page);

        {
            self.mu.lock();
            defer self.mu.unlock();

            if (self.pending_payload) |p| self.allocator.free(p);
            if (self.pending_combined) |p| self.allocator.free(p);
        }

        if (self.current_payload) |p| self.allocator.free(p);
        if (self.current_combined) |p| self.allocator.free(p);

        self.allocator.destroy(self);
    }

    fn acceptLoop(self: *SseServer) void {
        while (true) {
            {
                self.mu.lock();
                const stopped = self.stopped;
                self.mu.unlock();
                if (stopped) break;
            }

            const conn = self.listener.accept() catch {
                std.Thread.sleep(10 * std.time.ns_per_ms);
                continue;
            };

            self.accept_mu.lock();
            self.accept_queue.append(self.allocator, conn) catch {
                conn.stream.close();
            };
            self.accept_mu.unlock();
        }
    }

    // Event loop
    fn eventLoop(self: *SseServer) void {
        // Client registry: each entry is the raw stream for a connected SSE client.
        // Only accessed from this thread — no lock needed.
        var clients: std.ArrayList(std.net.Stream) = .empty;
        defer {
            for (clients.items) |c| c.close();
            clients.deinit(self.allocator);
        }

        const t = std.Thread.spawn(.{}, acceptLoop, .{self}) catch null;
        if (t) |thread| {
            self.mu.lock();
            self.accept_thread = thread;
            self.mu.unlock();
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

            std.Thread.sleep(100 * std.time.ns_per_ms);

            // Drain the accept queue into a local list before releasing the lock.
            // handleNewConn does a blocking read, so we must not hold accept_mu
            // while calling it — otherwise acceptLoop stalls waiting for the lock.
            var local_queue: std.ArrayList(std.net.Server.Connection) = .empty;
            defer local_queue.deinit(self.allocator);

            self.accept_mu.lock();
            for (self.accept_queue.items) |conn| {
                local_queue.append(self.allocator, conn) catch {
                    conn.stream.close();
                };
            }
            self.accept_queue.clearRetainingCapacity();
            self.accept_mu.unlock();

            for (local_queue.items) |conn| {
                self.handleNewConn(conn, &clients);
            }

            self.mu.lock();
            const payload = self.pending_payload;
            self.pending_payload = null;
            const combined = self.pending_combined;
            self.pending_combined = null;
            const reload = self.pending_reload;
            self.pending_reload = false;
            self.mu.unlock();

            if (payload) |p| {
                defer self.allocator.free(p);

                if (self.current_payload) |old| self.allocator.free(old);
                self.current_payload = self.allocator.dupe(u8, p) catch null;

                writePartsToAll(&clients, &.{ "event: report\ndata: ", p, "\n\n" });
            }

            if (combined) |p| {
                defer self.allocator.free(p);

                if (self.current_combined) |old| self.allocator.free(old);
                self.current_combined = self.allocator.dupe(u8, p) catch null;

                writePartsToAll(&clients, &.{ "event: combined_update\ndata: ", p, "\n\n" });
            }

            if (reload) {
                writePartsToAll(&clients, &.{"event: reload\ndata: {}\n\n"});
            }

            const now_ms = std.time.milliTimestamp();
            if (now_ms - last_keepalive_ms >= KEEPALIVE_MS) {
                writePartsToAll(&clients, &.{": keep-alive\n\n"});
                last_keepalive_ms = now_ms;
            }
        }
    }

    // Connection handling (called from event loop thread)
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
            const n = socketRecv(conn.stream.handle, buf[total..]) catch {
                gracefulClose(conn.stream);
                return;
            };
            if (n == 0) {
                gracefulClose(conn.stream);
                return;
            }
            total += n;
            if (std.mem.indexOf(u8, buf[0..total], "\r\n\r\n") != null) break;
            if (std.mem.indexOf(u8, buf[0..total], "\n\n") != null) break;
        }

        const line_end = std.mem.indexOf(u8, buf[0..total], "\r\n") orelse
            std.mem.indexOf(u8, buf[0..total], "\n") orelse {
            gracefulClose(conn.stream);
            return;
        };
        const first_line = buf[0..line_end];
        if (!std.mem.startsWith(u8, first_line, "GET ")) {
            gracefulClose(conn.stream);
            return;
        }
        const path_end = std.mem.indexOfPos(u8, first_line, 4, " ") orelse first_line.len;
        const req_path = first_line[4..path_end];

        if (std.mem.eql(u8, req_path, "/__events")) {
            self.upgradeSse(conn.stream, clients);
        } else {
            serveStatic(self.allocator, self.root_dir, self.default_page, req_path, conn.stream);
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
            gracefulClose(stream);
            return;
        };

        // Immediately push the last known combined_update so new clients get combined
        // data without waiting for the next file-change event.
        if (self.current_combined) |p| {
            const ok = blk: {
                stream.writeAll("event: combined_update\ndata: ") catch break :blk false;
                stream.writeAll(p) catch break :blk false;
                stream.writeAll("\n\n") catch break :blk false;
                break :blk true;
            };
            if (!ok) {
                gracefulClose(stream);
                return;
            }
        }

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
                gracefulClose(stream);
                return;
            }
        }

        clients.append(self.allocator, stream) catch {
            gracefulClose(stream);
            return;
        };
    }
};

// Helpers

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
            gracefulClose(clients.items[i]);
            _ = clients.swapRemove(i);
        } else {
            i += 1;
        }
    }
}

fn deriveMimeType(path: []const u8) []const u8 {
    if (std.mem.endsWith(u8, path, ".html")) return "text/html; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".json")) return "application/json";
    if (std.mem.endsWith(u8, path, ".css")) return "text/css";
    if (std.mem.endsWith(u8, path, ".js")) return "application/javascript";
    if (std.mem.endsWith(u8, path, ".md")) return "text/markdown";
    return "application/octet-stream";
}

fn serveStatic(allocator: std.mem.Allocator, root_dir: []const u8, default_page: []const u8, req_path_raw: []const u8, stream: std.net.Stream) void {
    defer gracefulClose(stream);

    // Strip leading slash and query string.
    var req_path = req_path_raw;
    if (req_path.len > 0 and req_path[0] == '/') req_path = req_path[1..];
    if (std.mem.indexOf(u8, req_path, "?")) |q| req_path = req_path[0..q];

    // Default to the configured HTML report.
    if (req_path.len == 0) req_path = default_page;

    // Reject path traversal.
    if (req_path[0] == '/' or std.mem.indexOf(u8, req_path, "..") != null) {
        stream.writeAll("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n") catch {};
        return;
    }

    const file_path = std.fs.path.join(allocator, &.{ root_dir, req_path }) catch return;
    defer allocator.free(file_path);

    const file = std.fs.cwd().openFile(file_path, .{}) catch {
        stream.writeAll("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n") catch {};
        return;
    };
    defer file.close();

    const file_size = file.getEndPos() catch {
        stream.writeAll("HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\n\r\n") catch {};
        return;
    };

    const mime = deriveMimeType(req_path);
    var hdr_buf: [256]u8 = undefined;
    const hdr = std.fmt.bufPrint(
        &hdr_buf,
        "HTTP/1.1 200 OK\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n",
        .{ mime, file_size },
    ) catch return;
    stream.writeAll(hdr) catch return;

    var buf: [64 * 1024]u8 = undefined;
    while (true) {
        const n = file.read(&buf) catch return;
        if (n == 0) break;
        stream.writeAll(buf[0..n]) catch return;
    }
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
