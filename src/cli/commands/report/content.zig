/// Facade — re-exports from the content sub-module.
pub const isBoilerplate = @import("content/content.zig").isBoilerplate;
pub const getCommentPrefix = @import("content/content.zig").getCommentPrefix;
pub const condenseContent = @import("content/content.zig").condenseContent;
