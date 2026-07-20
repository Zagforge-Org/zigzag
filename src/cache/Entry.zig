//! Top level struct representing cache entry.

mtime: u64, // The timestamp of when the original file was last modified
size: usize, // The size of the file in bytes
cache_filename: []u8, // The filename of the cached artifact
