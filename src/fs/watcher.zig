const builtin = @import("builtin");

const impl = if (builtin.os.tag == .linux)
    @import("watcher/linux.zig")
else if (builtin.os.tag == .windows)
    @import("watcher/windows.zig")
else if (builtin.os.tag == .macos or
    builtin.os.tag == .freebsd or
    builtin.os.tag == .netbsd or
    builtin.os.tag == .openbsd or
    builtin.os.tag == .dragonfly)
    @import("watcher/macos.zig")
else
    @compileError("--watch is not supported on " ++ @tagName(builtin.os.tag) ++
        ". Supported platforms: Linux, macOS, BSD, Windows.");

pub const WatchEventKind = impl.WatchEventKind;
pub const WatchEvent = impl.WatchEvent;

/// Platform-native filesystem watcher.
///
/// Usage:
///   var w = try Watcher.init(allocator);
///   defer w.deinit();
///   try w.watchDir("./src");
///   var events = std.ArrayList(WatchEvent).init(allocator);
///   defer events.deinit();
///   _ = try w.poll(&events, -1); // block until events
pub const Watcher = impl.Watcher;

// Pull in tests from the active platform implementation
test {
    _ = impl;
}
