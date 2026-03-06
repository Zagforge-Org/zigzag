/// Facade — re-exports from the paths sub-module.
pub const computeOutputSegment = @import("paths/paths.zig").computeOutputSegment;
pub const resolveOutputPath = @import("paths/paths.zig").resolveOutputPath;
pub const deriveJsonPath = @import("paths/paths.zig").deriveJsonPath;
pub const deriveHtmlPath = @import("paths/paths.zig").deriveHtmlPath;
pub const deriveLlmPath = @import("paths/paths.zig").deriveLlmPath;
