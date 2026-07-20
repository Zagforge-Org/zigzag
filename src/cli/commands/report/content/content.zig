const std = @import("std");

/// Exact filenames that are dependency lock files or generated manifests.
const BOILERPLATE = [_][]const u8{
    // JS/TS
    "package-lock.json",  "npm-shrinkwrap.json", "yarn.lock",       "pnpm-lock.yaml",
    "bun.lockb",          "bun.lock",
    // Go
               "go.sum",          "go.work.sum",
    // Rust
    "Cargo.lock",
    // Ruby
            "Gemfile.lock",
    // Python
           "poetry.lock",     "Pipfile.lock",
    // PHP
    "composer.lock",
    // Elixir / Dart / Nix / Deno
         "mix.lock",            "pubspec.lock",    "flake.lock",
    "deno.lock",
    // Swift / CocoaPods / Carthage
             "Package.resolved",    "Podfile.lock",    "Cartfile.resolved",
    // .NET / Java / Terraform
    "packages.lock.json", "paket.lock",          "gradle.lockfile", ".terraform.lock.hcl",
};

/// Filename suffixes that mark minified, bundled, or generated files.
const BOILERPLATE_EXTENSIONS = [_][]const u8{
    ".lock",
    ".min.js",
    ".min.mjs",
    ".min.css",
    ".bundle.js",
    ".chunk.js",
    ".map",
    ".pb.go",
    ".pb.cc",
    ".pb.h",
    "_pb2.py",
    "_pb2_grpc.py",
    ".g.dart",
    ".freezed.dart",
    ".snap",
};

/// Extensions whose single-line comments start with `//`.
const SLASH_COMMENT_EXTENSIONS = [_][]const u8{
    ".zig",    ".js",    ".ts",  ".jsx",  ".tsx",  ".mjs",  ".cjs",
    ".rs",     ".go",    ".c",   ".h",    ".cpp",  ".cc",   ".cxx",
    ".hpp",    ".hh",    ".hxx", ".cu",   ".cuh",  ".java", ".scala",
    ".swift",  ".kt",    ".kts", ".cs",   ".dart", ".php",  ".groovy",
    ".gradle", ".proto", ".sol", ".glsl", ".hlsl", ".wgsl", ".mm",
    ".jsonc",
};

/// Extensions whose single-line comments start with `#`.
const HASH_COMMENT_EXTENSIONS = [_][]const u8{
    ".py",    ".sh",   ".bash",    ".zsh", ".fish", ".ps1",
    ".rb",    ".rake", ".gemspec", ".pl",  ".r",    ".jl",
    ".ex",    ".exs",  ".nim",     ".cr",  ".tcl",  ".nix",
    ".cmake", ".mk",   ".yaml",    ".yml", ".toml",
};

/// Extensions whose single-line comments start with `--`.
const DASH_COMMENT_EXTENSIONS = [_][]const u8{
    ".sql", ".lua", ".hs", ".elm", ".purs", ".vhd", ".vhdl", ".adb", ".ads",
};

/// Extensions whose single-line comments start with `%`.
const PERCENT_COMMENT_EXTENSIONS = [_][]const u8{
    ".tex", ".sty", ".cls", ".bib", ".erl", ".hrl",
};

fn matchesAny(needle: []const u8, haystack: []const []const u8) bool {
    for (haystack) |item| {
        if (std.mem.eql(u8, needle, item)) return true;
    }
    return false;
}

/// Returns true if the filename matches known boilerplate patterns.
pub fn isBoilerplate(filename: []const u8) bool {
    if (matchesAny(filename, &BOILERPLATE)) return true;
    for (BOILERPLATE_EXTENSIONS) |ext| {
        if (std.mem.endsWith(u8, filename, ext)) return true;
    }
    return std.mem.indexOf(u8, filename, ".generated.") != null;
}

/// Returns the single-line comment prefix for the given file extension, or null if unknown.
pub fn getCommentPrefix(extension: []const u8) ?[]const u8 {
    if (matchesAny(extension, &SLASH_COMMENT_EXTENSIONS)) return "//";
    if (matchesAny(extension, &HASH_COMMENT_EXTENSIONS)) return "#";
    if (matchesAny(extension, &DASH_COMMENT_EXTENSIONS)) return "--";
    if (matchesAny(extension, &PERCENT_COMMENT_EXTENSIONS)) return "%";
    return null;
}

/// Condenses file content for LLM ingestion:
/// - Strips single-line comments (by extension)
/// - Collapses consecutive blank lines to 1
/// - Truncates files over max_lines to first 60 + last 20 lines
/// Returns caller-owned slice.
pub fn condenseContent(
    allocator: std.mem.Allocator,
    content: []const u8,
    extension: []const u8,
    max_lines: u64,
) ![]u8 {
    const comment_prefix = getCommentPrefix(extension);

    var condensed: std.ArrayList([]const u8) = .empty;
    defer condensed.deinit(allocator);

    var prev_blank = false;
    var iter = std.mem.splitScalar(u8, content, '\n');
    while (iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        if (comment_prefix) |pfx| {
            if (std.mem.startsWith(u8, trimmed, pfx)) continue;
        }

        const is_blank = trimmed.len == 0;
        if (is_blank) {
            if (prev_blank) continue;
            prev_blank = true;
        } else {
            prev_blank = false;
        }

        try condensed.append(allocator, line);
    }

    // A trailing empty string from splitting a newline-terminated file is not
    // a real line; exclude it from the count but preserve it for the join so
    // that the output retains a trailing newline.
    const has_trailing_empty = condensed.items.len > 0 and
        condensed.items[condensed.items.len - 1].len == 0;
    const real_lines: u64 = @intCast(if (has_trailing_empty) condensed.items.len - 1 else condensed.items.len);
    const head: usize = 60;
    const tail: usize = 20;
    if (real_lines <= max_lines or real_lines <= head + tail) {
        return std.mem.join(allocator, "\n", condensed.items);
    }
    const total = real_lines;
    const omitted = total - (head + tail);

    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    const writer = &out.writer;

    for (condensed.items[0..head]) |line| {
        try writer.writeAll(line);
        try writer.writeByte('\n');
    }

    try writer.print("// [{d} lines omitted]\n", .{omitted});

    const real_items = if (has_trailing_empty)
        condensed.items[0 .. condensed.items.len - 1]
    else
        condensed.items;
    const start_tail = real_items.len - tail;
    for (real_items[start_tail..]) |line| {
        try writer.writeAll(line);
        try writer.writeByte('\n');
    }

    return out.toOwnedSlice();
}
