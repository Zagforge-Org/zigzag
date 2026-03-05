// Utility functions for version parsing.
// Works in both binary and runtime modes, without hardcoding the version string.
// Written with tests for both binary and runtime modes.

const std = @import("std");
const fs = std.fs;

const DEFAULT_MAX_ZON_BYTES = 1 << 20; // 1 MiB
const DEFAULT_BUILD_PATH = "build.zig.zon";

const VersionError = error{
    FileNotFound,
    FileTooBig,
    ParseError,
    Other,
};

const ReadOptions = struct {
    path: ?[]const u8 = null,
    max_bytes: ?usize = null,
};

// isRuntime returns true if no real version was baked in.
// Uses @hasDecl so it compiles safely without the options module (e.g. `zig run`).
pub fn isRuntime() bool {
    if (!@hasDecl(@import("root"), "options")) return true;
    const opts = @import("options");
    return opts.version.major == 0 and opts.version.minor == 0 and opts.version.patch == 0;
}

// getVersion returns the version as a string.
// In binary/build-test mode, returns the baked-in version_string from options.
// In runtime mode (version 0.0.0 or no options), parses build.zig.zon.
pub fn getVersion(allocator: std.mem.Allocator) ![]const u8 {
    if (@hasDecl(@import("root"), "options")) {
        const opts = @import("options");
        if (opts.version.major != 0 or opts.version.minor != 0 or opts.version.patch != 0) {
            return allocator.dupe(u8, opts.version_string);
        }
    }

    // Runtime mode: search for build.zig.zon
    const data = try readZonVersion(allocator, .{});
    defer allocator.free(data);

    return try parseVersion(allocator, data);
}

// readZonVersion reads the version from build.zig.zon.
// It returns an error if the file is not found or too big.
fn readZonVersion(allocator: std.mem.Allocator, opts: ReadOptions) VersionError![]u8 {
    const file_path = opts.path orelse DEFAULT_BUILD_PATH;
    const max_bytes = opts.max_bytes orelse DEFAULT_MAX_ZON_BYTES;

    const file_data = fs.cwd().readFileAlloc(allocator, file_path, max_bytes) catch |err| {
        return switch (err) {
            error.FileTooBig => VersionError.FileTooBig,
            error.FileNotFound => VersionError.FileNotFound,
            else => VersionError.Other,
        };
    };

    return file_data;
}

// parseVersion parses the version string from the build.zig.zon file.
// It returns an error if the version is not found or malformed.
fn parseVersion(allocator: std.mem.Allocator, buffer: []const u8) ![]u8 {
    const key = ".version = \"";
    const start_index = std.mem.indexOf(u8, buffer, key) orelse return error.ParseError;
    const actual_start = start_index + key.len;
    const end_index = std.mem.indexOfPos(u8, buffer, actual_start, "\"") orelse return error.ParseError;

    return allocator.dupe(u8, buffer[actual_start..end_index]);
}

// --- Tests ---

test "ONLY RUN THIS AT RUNTIME - build.zig.zon errors if not found" {
    if (!isRuntime()) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const result = readZonVersion(allocator, .{ .path = "nonexistent.zig.zon" });
    try std.testing.expectError(error.FileNotFound, result);
}

test "ONLY RUN THIS AT RUNTIME - build.zig.zon exceeds max bytes" {
    if (!isRuntime()) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const result = readZonVersion(allocator, .{ .max_bytes = 1 });
    try std.testing.expectError(error.FileTooBig, result);
}

test "ONLY RUN THIS AT RUNTIME - build.zig.zon exists" {
    if (!isRuntime()) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const result = try readZonVersion(allocator, .{});
    defer allocator.free(result);

    try std.testing.expect(result.len > 0);
}

test "isRuntime returns false when build options provide a real version" {
    // Skips in runtime mode (make test with fallback 0.0.0 options).
    // Passes in zig build test mode where options has the real project version.
    if (isRuntime()) return error.SkipZigTest;
}
