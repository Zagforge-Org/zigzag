const std = @import("std");

pub const Context = struct { ignore_list: std.ArrayList([]const u8) };
