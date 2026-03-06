// Fallback options module used when compiling outside the build system
// (e.g. `zig test src/root.zig -Moptions=src/cli/options_fallback.zig`).
// Version 0.0.0 signals runtime mode: getVersion() falls back to build.zig.zon.
const std = @import("std");

pub const version = std.SemanticVersion{ .major = 0, .minor = 0, .patch = 0 };
pub const version_string: []const u8 = "0.0.0";
