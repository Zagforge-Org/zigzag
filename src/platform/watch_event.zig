//! Filesystem watch event shared across the platform watcher implementations.

pub const WatchEventKind = enum { modified, created, deleted };

pub const WatchEvent = struct {
    path: []const u8,
    kind: WatchEventKind,
};
