//! Global `˙Io` handle for Zig 0.16.0 filesystem and I/O APIs.
//! In 0.16.0 every `Io.Dir / Io.File` operation takes `io: Io`.

const std = @import("std");
const builtin = @import("builtin");

// In test builds there is no `main` to call `setIo`, so default the global handle
// to test runner's threaded Io.
var instance: std.Io = if (builtin.is_test) std.testing.io else undefined;
var env_map: ?*const std.process.Environ.Map = null;

/// Called once before any filesystem/I/O work.
pub fn setIo(io_handle: std.Io) void {
    instance = io_handle;
}

/// The global Io handle.
pub fn io() std.Io {
    return instance;
}

/// Called once at startup with the process environment.
pub fn setEnviron(map: *const std.process.Environ.Map) void {
    env_map = map;
}

/// Look up an environment variable, returning a borrowed slice that lives for
/// the duration of the process.
pub fn getEnv(key: []const u8) ?[]const u8 {
    const map = env_map orelse return null;
    return map.get(key);
}
