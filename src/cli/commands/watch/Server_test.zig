const std = @import("std");
const Server = @import("Server.zig");

test "Server.init creates server and sets bound_port" {
    const alloc = std.testing.allocator;
    const srv = try Server.init(std.testing.io, 0, "/tmp", "report.html", alloc);
    defer srv.deinit();
    try std.testing.expectEqual(@as(u16, 0), srv.bound_port);
    try std.testing.expectEqualStrings("/tmp", srv.root_dir);
    try std.testing.expectEqualStrings("report.html", srv.default_page);
}

test "Server.broadcast queues a payload" {
    const alloc = std.testing.allocator;
    const srv = try Server.init(std.testing.io, 0, "/tmp", "report.html", alloc);
    defer srv.deinit();

    srv.broadcast("hello world");

    srv.mu.lockUncancelable(std.testing.io);
    const payload = srv.pending_payload;
    srv.mu.unlock(std.testing.io);

    try std.testing.expect(payload != null);
    try std.testing.expectEqualStrings("hello world", payload.?);
}

test "Server.broadcast replaces a previous pending payload" {
    const alloc = std.testing.allocator;
    const srv = try Server.init(std.testing.io, 0, "/tmp", "report.html", alloc);
    defer srv.deinit();

    srv.broadcast("first");
    srv.broadcast("second");

    srv.mu.lockUncancelable(std.testing.io);
    const payload = srv.pending_payload;
    srv.mu.unlock(std.testing.io);

    try std.testing.expect(payload != null);
    try std.testing.expectEqualStrings("second", payload.?);
}

test "Server.broadcastReload sets pending_reload flag" {
    const alloc = std.testing.allocator;
    const srv = try Server.init(std.testing.io, 0, "/tmp", "report.html", alloc);
    defer srv.deinit();

    srv.broadcastReload();

    srv.mu.lockUncancelable(std.testing.io);
    const reload = srv.pending_reload;
    srv.mu.unlock(std.testing.io);

    try std.testing.expect(reload);
}

test "Server.stop sets stopped flag" {
    const alloc = std.testing.allocator;
    const srv = try Server.init(std.testing.io, 0, "/tmp", "report.html", alloc);
    defer srv.deinit();

    srv.stop();

    srv.mu.lockUncancelable(std.testing.io);
    const stopped = srv.stopped;
    srv.mu.unlock(std.testing.io);

    try std.testing.expect(stopped);
}

test "Server.deinit frees pending_payload without leak" {
    const alloc = std.testing.allocator;
    const srv = try Server.init(std.testing.io, 0, "/tmp", "report.html", alloc);
    srv.broadcast("pending data that must be freed");
    srv.deinit(); // must not leak
}
