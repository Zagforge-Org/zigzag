/// FileError represents an error that occurred while working with a file.
/// Works in a cross-platform manner.
pub const FileError = error{
    EmptyFile,
    MapViewFailed,
    MMapFailed,
};
