const std = @import("std");

const ENABLE_VIRTUAL_TERMINAL_PROCESSING: std.os.windows.DWORD = 0x0004;

const win_console = struct {
    extern "kernel32" fn GetConsoleMode(
        hConsoleHandle: std.os.windows.HANDLE,
        lpMode: *std.os.windows.DWORD,
    ) callconv(.winapi) std.os.windows.BOOL;

    extern "kernel32" fn SetConsoleMode(
        hConsoleHandle: std.os.windows.HANDLE,
        dwMode: std.os.windows.DWORD,
    ) callconv(.winapi) std.os.windows.BOOL;
};

/// Enables ANSI escape sequence support on the Windows stderr console.
pub fn enableAnsi() void {
    const stderr = std.Io.File.stderr();

    var mode: std.os.windows.DWORD = 0;

    if (win_console.GetConsoleMode(stderr.handle, &mode) == .FALSE)
        return;

    _ = win_console.SetConsoleMode(
        stderr.handle,
        mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING,
    );
}
