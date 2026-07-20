//! Platform-native filesystem watcher dispatches to the OS implementation.

const builtin = @import("builtin");

const impl = if (builtin.os.tag == .linux)
    @import("linux/Watcher.zig")
else if (builtin.os.tag == .windows)
    @import("windows/Watcher.zig")
else if (builtin.os.tag == .macos or
    builtin.os.tag == .freebsd or
    builtin.os.tag == .netbsd or
    builtin.os.tag == .openbsd or
    builtin.os.tag == .dragonfly)
    @import("macos/Watcher.zig")
else
    @compileError("--watch is not supported on " ++ @tagName(builtin.os.tag) ++
        ". Supported platforms: Linux, macOS, BSD, Windows.");

pub const WatchEventKind = @import("watch_event.zig").WatchEventKind;
pub const WatchEvent = @import("watch_event.zig").WatchEvent;

/// Platform-native filesystem watcher.
///
/// Usage:
///   var w = try Watcher.init(io, allocator);
///   defer w.deinit();
///   try w.watchDir("./src");
///   var events: std.ArrayList(WatchEvent) = .empty;
///   defer events.deinit(allocator);
///   _ = try w.poll(&events, -1); // block until events
pub const Watcher = impl;
