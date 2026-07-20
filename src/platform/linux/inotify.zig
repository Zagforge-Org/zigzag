//! Thin shims over the raw `std.os.linux` inotify syscalls, reproducing the
//! errno-to-error mapping the old `std.posix` helpers provided.

const std = @import("std");
const linux = std.os.linux;
const posix = std.posix;

const InitError = error{
    ProcessFdQuotaExceeded,
    SystemFdQuotaExceeded,
    SystemResources,
} || posix.UnexpectedError;

const AddWatchError = error{
    AccessDenied,
    NameTooLong,
    FileNotFound,
    SystemResources,
    UserResourceLimitReached,
    NotDir,
    WatchAlreadyExists,
} || posix.UnexpectedError;

pub fn init1(flags: u32) InitError!i32 {
    const rc = linux.inotify_init1(flags);
    return switch (posix.errno(rc)) {
        .SUCCESS => @intCast(rc),
        .INVAL => unreachable,
        .MFILE => error.ProcessFdQuotaExceeded,
        .NFILE => error.SystemFdQuotaExceeded,
        .NOMEM => error.SystemResources,
        else => |err| posix.unexpectedErrno(err),
    };
}

pub fn addWatchZ(inotify_fd: i32, pathname: [*:0]const u8, mask: u32) AddWatchError!i32 {
    const rc = linux.inotify_add_watch(inotify_fd, pathname, mask);
    return switch (posix.errno(rc)) {
        .SUCCESS => @intCast(rc),
        .ACCES => error.AccessDenied,
        .BADF => unreachable,
        .FAULT => unreachable,
        .INVAL => unreachable,
        .NAMETOOLONG => error.NameTooLong,
        .NOENT => error.FileNotFound,
        .NOMEM => error.SystemResources,
        .NOSPC => error.UserResourceLimitReached,
        .NOTDIR => error.NotDir,
        .EXIST => error.WatchAlreadyExists,
        else => |err| posix.unexpectedErrno(err),
    };
}
