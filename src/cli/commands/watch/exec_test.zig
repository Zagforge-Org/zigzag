const std = @import("std");
const Config = @import("../config/Config.zig");
const execWatch = @import("exec.zig").execWatch;

test "execWatch returns immediately when no paths configured" {
    var cfg = Config.default(std.testing.allocator);
    defer cfg.deinit();
    // cfg.paths is empty — execWatch must return without entering the event loop
    try execWatch(std.testing.io, &cfg, null, std.testing.allocator);
}

test "execWatch returns when every configured path fails to scan" {
    const alloc = std.testing.allocator;
    var cfg = Config.default(alloc);
    defer cfg.deinit();
    // A path that can't be opened as a directory: scanPath logs and yields null, so no
    // State is collected. With states empty, execWatch must return before the (infinite)
    // watch loop rather than block. cfg.deinit frees the duped path.
    try cfg.paths.append(alloc, try alloc.dupe(u8, "zzz-nonexistent-watch-dir-xyz"));
    try execWatch(std.testing.io, &cfg, null, alloc);
}
