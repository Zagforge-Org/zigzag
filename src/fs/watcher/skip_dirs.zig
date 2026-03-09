/// Directories skipped by the file walker (shouldIgnore in process.zig).
/// The watcher must skip the same dirs so their writes never enter the inotify queue.
/// Matching is substring-based (same as matchesPattern path-contains logic).
pub const DEFAULT_SKIP_DIRS = [_][]const u8{
    "node_modules",
    ".git",
    ".svn",
    ".hg",
    "__pycache__",
    ".pytest_cache",
    ".idea",
    ".vscode",
    ".DS_Store",
    ".cache",
    ".zig-cache",
};
