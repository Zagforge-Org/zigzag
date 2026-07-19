/// Single entry point for all utils sub-modules.
pub const Color = @import("./colors/colors.zig").Color;
pub const colorCode = @import("./colors/colors.zig").colorCode;

pub const fmtBytes = @import("./fmt/fmt.zig").fmtBytes;
pub const fmtElapsed = @import("./fmt/fmt.zig").fmtElapsed;
pub const fmtMilliseconds = @import("./fmt/fmt.zig").fmtMilliseconds;

pub const Progress = @import("../progress/Progress.zig");

pub const DEFAULT_SKIP_DIRS = @import("./skip_dirs/skip_dirs.zig").DEFAULT_SKIP_DIRS;
