const std = @import("std");

/// FileContext represents the context for processing a file.
pub const FileContext = struct {
    ignore_list: std.ArrayList([]const u8),
    md: *std.fs.File,
    md_mutex: *std.Thread.Mutex,
};
