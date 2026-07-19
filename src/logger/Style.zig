//! ANSI style constants and symbols for logger output.

// Colors
pub const reset = "\x1b[0m";
pub const bold = "\x1b[1m";
pub const dim = "\x1b[90m"; // bright black
pub const green = "\x1b[92m"; // bright green
pub const white = "\x1b[97m"; // bright white

// Symbols
pub const rocket = "🚀"; // report banner
pub const check = "✔"; // generated-report entry
pub const badge = "✅"; // footer "all done"
pub const bullet = "•"; // highlight bullet

// Section decorations
pub const section = dim ++ "─" ** 40 ++ reset ++ "\n";
pub const rule = dim ++ "─" ** 36 ++ reset ++ "\n";
