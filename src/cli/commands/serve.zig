/// Facade — re-exports the serve command implementation.
const serve = @import("serve/serve.zig");

pub const ServeConfig = serve.ServeConfig;
pub const deriveMimeType = serve.deriveMimeType;
pub const isPathSafe = serve.isPathSafe;
pub const execServe = serve.execServe;
