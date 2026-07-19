const std = @import("std");

/// FileContext represents the context for processing a file.
pub const FileContext = struct {
    io: std.Io,
    ignore_list: std.ArrayList([]const u8),
    md: *std.Io.File,
    md_mutex: *std.Io.Mutex,
};
