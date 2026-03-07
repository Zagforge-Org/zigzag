const std = @import("std");
const SseServer = @import("server.zig").SseServer;

test "SseServer.init creates server and sets bound_port" {
    const alloc = std.testing.allocator;
    const srv = try SseServer.init(0, "/tmp", "report.html", alloc);
    defer srv.deinit();
    try std.testing.expectEqual(@as(u16, 0), srv.bound_port);
    try std.testing.expectEqualStrings("/tmp", srv.root_dir);
    try std.testing.expectEqualStrings("report.html", srv.default_page);
}

test "SseServer.broadcast queues a payload" {
    const alloc = std.testing.allocator;
    const srv = try SseServer.init(0, "/tmp", "report.html", alloc);
    defer srv.deinit();

    srv.broadcast("hello world");

    srv.mu.lock();
    const payload = srv.pending_payload;
    srv.mu.unlock();

    try std.testing.expect(payload != null);
    try std.testing.expectEqualStrings("hello world", payload.?);
}

test "SseServer.broadcast replaces a previous pending payload" {
    const alloc = std.testing.allocator;
    const srv = try SseServer.init(0, "/tmp", "report.html", alloc);
    defer srv.deinit();

    srv.broadcast("first");
    srv.broadcast("second");

    srv.mu.lock();
    const payload = srv.pending_payload;
    srv.mu.unlock();

    try std.testing.expect(payload != null);
    try std.testing.expectEqualStrings("second", payload.?);
}

test "SseServer.broadcastReload sets pending_reload flag" {
    const alloc = std.testing.allocator;
    const srv = try SseServer.init(0, "/tmp", "report.html", alloc);
    defer srv.deinit();

    srv.broadcastReload();

    srv.mu.lock();
    const reload = srv.pending_reload;
    srv.mu.unlock();

    try std.testing.expect(reload);
}

test "SseServer.stop sets stopped flag" {
    const alloc = std.testing.allocator;
    const srv = try SseServer.init(0, "/tmp", "report.html", alloc);
    defer srv.deinit();

    srv.stop();

    srv.mu.lock();
    const stopped = srv.stopped;
    srv.mu.unlock();

    try std.testing.expect(stopped);
}

test "SseServer.deinit frees pending_payload without leak" {
    const alloc = std.testing.allocator;
    const srv = try SseServer.init(0, "/tmp", "report.html", alloc);
    srv.broadcast("pending data that must be freed");
    srv.deinit(); // must not leak
}
