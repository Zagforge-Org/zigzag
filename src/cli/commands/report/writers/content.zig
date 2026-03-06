/// Facade — re-exports content helpers for writer sub-modules that import ../content.zig.
pub const isBoilerplate = @import("../content/content.zig").isBoilerplate;
pub const getCommentPrefix = @import("../content/content.zig").getCommentPrefix;
pub const condenseContent = @import("../content/content.zig").condenseContent;
