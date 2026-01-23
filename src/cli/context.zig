const std = @import("std");

pub const FileContext = struct {
    ignore_list: std.ArrayList([]const u8),
    md: *std.fs.File,
    md_mutex: *std.Thread.Mutex,
};
