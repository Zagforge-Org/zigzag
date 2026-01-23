pub const CacheEntry = struct {
    mtime: u64,
    size: usize,
    cache_filename: []u8,
};
