const std = @import("std");
const Config = @import("../config/config.zig").Config;
const execWatch = @import("exec.zig").execWatch;

test "execWatch returns immediately when no paths configured" {
    var cfg = Config.default(std.testing.allocator);
    defer cfg.deinit();
    // cfg.paths is empty — execWatch must return without entering the event loop
    try execWatch(&cfg, null, std.testing.allocator);
}
