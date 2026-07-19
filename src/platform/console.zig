//! Terminal control, dispatched per platform.

const builtin = @import("builtin");

/// Enables ANSI escape processing on the terminal. No-op except on Windows.
pub fn enableAnsi() void {
    if (comptime builtin.os.tag == .windows) {
        @import("windows/console.zig").enableAnsi();
    }
}
