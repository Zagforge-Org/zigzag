//! Thin shims over the BSD kqueue syscalls (macOS/BSD).

const std = @import("std");
const posix = std.posix;
const c = std.c;

pub fn kqueue() !posix.fd_t {
    const rc = c.kqueue();
    if (rc < 0) return error.KqueueInit;
    return rc;
}

pub fn kevent(
    kq: posix.fd_t,
    changelist: []const posix.Kevent,
    eventlist: []posix.Kevent,
    timeout: ?*const posix.timespec,
) !usize {
    const rc = c.kevent(
        kq,
        changelist.ptr,
        @intCast(changelist.len),
        eventlist.ptr,
        @intCast(eventlist.len),
        timeout,
    );
    if (rc < 0) return error.Kevent;
    return @intCast(rc);
}

pub fn fstat(fd: posix.fd_t) !c.Stat {
    var st: c.Stat = undefined;
    if (c.fstat(fd, &st) < 0) return error.Fstat;
    return st;
}

pub fn close(fd: posix.fd_t) void {
    _ = c.close(fd);
}
