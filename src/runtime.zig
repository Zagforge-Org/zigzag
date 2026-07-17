//! Global `˙Io` handle for Zig 0.16.0 filesystem and I/O APIs.
//! In 0.16.0 every `Io.Dir / Io.File` operation takes `io: Io`.

const std = @import("std");

var instance: std.Io = undefined;

/// Called once before any filesystem/I/O work.
pub fn setIo(io_handle: std.Io) void {
    instance = io_handle;
}

/// The global Io handle.
pub fn io() std.Io {
    return instance;
}
