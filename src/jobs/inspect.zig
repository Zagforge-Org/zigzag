//! File inspection helpers: extension parsing, binary detection, and
//! ignore-pattern matching.

const std = @import("std");
const DEFAULT_SKIP_DIRS = @import("../utils/utils.zig").DEFAULT_SKIP_DIRS;

const BINARY_EXTENSIONS = [_][]const u8{
    // images
    ".png",     ".jpg",      ".jpeg",  ".gif",  ".bmp",   ".ico",         ".webp",
    ".tiff",    ".tif",      ".heic",  ".heif", ".avif",  ".jxl",         ".psd",
    ".ai",      ".cr2",      ".nef",   ".dng",  ".raw",   ".svgz",
    // documents
           ".pdf",
    ".doc",     ".docx",     ".xls",   ".xlsx", ".ppt",   ".pptx",        ".odt",
    ".ods",     ".odp",      ".epub",  ".mobi", ".azw3",
    // archives / compressed
     ".zip",         ".tar",
    ".gz",      ".tgz",      ".bz2",   ".tbz2", ".7z",    ".rar",         ".xz",
    ".lz4",     ".lzma",     ".zst",   ".zstd", ".cab",   ".deb",         ".rpm",
    ".dmg",     ".iso",      ".img",   ".apk",
    // executables / objects / libraries
     ".exe",   ".msi",         ".dll",
    ".so",      ".dylib",    ".bin",   ".o",    ".a",     ".lib",         ".wasm",
    ".pdb",     ".elf",      ".ko",    ".sys",  ".class", ".jar",         ".war",
    ".aar",     ".dex",      ".nupkg",
    // databases / binary data
    ".dat",  ".db",    ".sqlite",      ".sqlite3",
    ".mdb",     ".accdb",    ".dbf",   ".npy",  ".npz",   ".h5",          ".hdf5",
    ".parquet", ".feather",  ".arrow", ".pb",
    // bytecode / compiled artifacts
      ".pyc",   ".pyo",         ".pyd",
    ".whl",     ".egg",      ".beam",  ".elc",  ".luac",  ".rlib",        ".rmeta",
    ".mo",
    // ml model weights
         ".pt",       ".pth",   ".ckpt", ".onnx",  ".safetensors", ".pkl",
    ".pickle",  ".joblib",
    // audio
      ".mp3",   ".wav",  ".flac",  ".aac",         ".ogg",
    ".oga",     ".opus",     ".m4a",   ".wma",  ".aiff",  ".mid",         ".midi",
    // video
    ".mp4",     ".avi",      ".mov",   ".mkv",  ".wmv",   ".flv",         ".webm",
    ".m4v",     ".mpg",      ".mpeg",  ".3gp",  ".vob",   ".ogv",
    // fonts
            ".woff",
    ".woff2",   ".ttf",      ".otf",   ".eot",  ".ttc",
    // certificates / keystores
      ".der",         ".p12",
    ".pfx",     ".keystore", ".jks",
    // disk / vm images
      ".vmdk", ".vdi",   ".qcow2",       ".ova",
    // misc binary
    ".swf",     ".blend",    ".glb",   ".pak",  ".wad",
};

fn basename(path: []const u8) []const u8 {
    var lastSlash: usize = 0;
    var i: usize = 0;
    while (i < path.len) : (i += 1) {
        if (path[i] == '/' or path[i] == '\\') lastSlash = i + 1;
    }
    return path[lastSlash..];
}

pub fn getExtension(path: []const u8) []const u8 {
    const name = basename(path);
    var i: usize = name.len;
    while (i > 0) {
        i -= 1;
        if (name[i] == '.') {
            return name[i..];
        }
    }
    return "";
}

/// Check if a file is binary by examining its extension and/or content.
pub fn isBinaryFile(path: []const u8, content: []const u8) bool {
    const ext = getExtension(path);

    // Check extension first (faster)
    for (BINARY_EXTENSIONS) |binary_ext| {
        if (std.ascii.eqlIgnoreCase(ext, binary_ext)) {
            return true;
        }
    }

    // Heuristic: check for null bytes or high ratio of non-printable characters
    // Only check first 512 bytes for performance
    const check_len = @min(content.len, 512);
    var non_printable: usize = 0;

    for (content[0..check_len]) |byte| {
        if (byte == 0) return true; // Null byte = binary
        if (byte < 32 and byte != '\n' and byte != '\r' and byte != '\t') {
            non_printable += 1;
        }
    }

    // If more than 30% non-printable, consider it binary
    if (check_len > 0 and (non_printable * 100 / check_len) > 30) {
        return true;
    }

    return false;
}

/// Improved pattern matching for ignore patterns.
fn matchesPattern(path: []const u8, pattern: []const u8) bool {
    const filename = basename(path);

    // Wildcard extension pattern: *.ext
    if (pattern.len >= 2 and pattern[0] == '*' and pattern[1] == '.') {
        const ext = getExtension(filename);
        return std.ascii.eqlIgnoreCase(ext, pattern[1..]);
    }

    // Wildcard prefix pattern: prefix*
    if (pattern.len >= 2 and pattern[pattern.len - 1] == '*') {
        const prefix = pattern[0 .. pattern.len - 1];
        return std.mem.startsWith(u8, filename, prefix);
    }

    // Wildcard suffix pattern: *suffix
    if (pattern.len >= 2 and pattern[0] == '*') {
        const suffix = pattern[1..];
        return std.mem.endsWith(u8, filename, suffix);
    }

    // Exact filename match
    if (std.mem.eql(u8, filename, pattern)) {
        return true;
    }

    // Path contains pattern (for directories like node_modules, .cache, etc.)
    if (std.mem.indexOf(u8, path, pattern) != null) {
        return true;
    }

    return false;
}

pub fn shouldIgnore(file: []const u8, ignore_list: std.ArrayList([]const u8)) bool {
    for (DEFAULT_SKIP_DIRS) |pattern| {
        if (std.mem.indexOf(u8, file, pattern) != null) {
            return true;
        }
    }

    // Check user-provided ignore patterns
    for (ignore_list.items) |pattern| {
        if (matchesPattern(file, pattern)) {
            return true;
        }
    }

    return false;
}

/// Count lines in a content buffer.
/// Each '\n' counts as a line separator; if the content doesn't end with '\n',
/// the last partial line is still counted.
pub fn countLines(content: []const u8) usize {
    if (content.len == 0) return 0;
    var count: usize = 0;
    for (content) |c| {
        if (c == '\n') count += 1;
    }
    if (content[content.len - 1] != '\n') count += 1;
    return count;
}
