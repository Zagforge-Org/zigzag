/// Directories skipped by the file walker (shouldIgnore in process.zig).
/// The watcher skips the same dirs so their writes never enter the OS event queue.
/// Matching is substring-based (path-contains).
pub const DEFAULT_SKIP_DIRS = [_][]const u8{
    "node_modules",
    ".git",
    ".svn",
    ".hg",
    "__pycache__",
    ".pytest_cache",
    "target",
    "build",
    "dist",
    ".idea",
    ".vscode",
    ".DS_Store",
    ".cache",
    ".zig-cache",
    ".turbo",
    ".nx",
    ".parcel-cache",
    "zig.conf.json",
};
