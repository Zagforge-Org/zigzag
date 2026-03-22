const std = @import("std");
const gitBlobSha = @import("./upload.zig").gitBlobSha;
const parseApiKeyFromCredentials = @import("./upload.zig").parseApiKeyFromCredentials;
const resolveUploadUrl = @import("./upload.zig").resolveUploadUrl;

test "gitBlobSha: empty content matches git empty-blob SHA" {
    // git hash-object /dev/null → e69de29bb2d1d6434b8b29ae775ad8c2e48c5391
    var out: [40]u8 = undefined;
    gitBlobSha("", &out);
    try std.testing.expectEqualStrings("e69de29bb2d1d6434b8b29ae775ad8c2e48c5391", &out);
}

test "gitBlobSha: 'hello\\n' matches known git SHA" {
    // echo -n 'hello\n' | git hash-object → ce013625030ba8dba906f756967f9e9ca394464a
    var out: [40]u8 = undefined;
    gitBlobSha("hello\n", &out);
    try std.testing.expectEqualStrings("ce013625030ba8dba906f756967f9e9ca394464a", &out);
}

test "gitBlobSha: output is always 40 hex characters" {
    var out: [40]u8 = undefined;
    gitBlobSha("some content here", &out);
    for (out) |c| {
        try std.testing.expect((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f'));
    }
}

test "parseApiKeyFromCredentials: extracts key from well-formed file" {
    const allocator = std.testing.allocator;
    const contents = "# Zagforge credentials\nZAGFORGE_API_KEY=zf_pk_testtoken123\n";
    const key = parseApiKeyFromCredentials(allocator, contents);
    defer if (key) |k| allocator.free(k);
    try std.testing.expect(key != null);
    try std.testing.expectEqualStrings("zf_pk_testtoken123", key.?);
}

test "parseApiKeyFromCredentials: returns null when key is absent" {
    const allocator = std.testing.allocator;
    const contents = "# no key here\nSOME_OTHER_VAR=value\n";
    const key = parseApiKeyFromCredentials(allocator, contents);
    try std.testing.expect(key == null);
}

test "parseApiKeyFromCredentials: handles empty file" {
    const allocator = std.testing.allocator;
    const key = parseApiKeyFromCredentials(allocator, "");
    try std.testing.expect(key == null);
}

test "parseApiKeyFromCredentials: handles key with no trailing newline" {
    const allocator = std.testing.allocator;
    const key = parseApiKeyFromCredentials(allocator, "ZAGFORGE_API_KEY=zf_pk_abc");
    defer if (key) |k| allocator.free(k);
    try std.testing.expect(key != null);
    try std.testing.expectEqualStrings("zf_pk_abc", key.?);
}

test "resolveUploadUrl: returns default URL when env var is absent" {
    const allocator = std.testing.allocator;
    // ZAGFORGE_API_URL is unlikely to be set in the test environment.
    // If it is, this test still passes (URL will still end with the path).
    const url = try resolveUploadUrl(allocator);
    defer allocator.free(url);
    try std.testing.expect(std.mem.endsWith(u8, url, "/api/v1/upload"));
}

test "resolveUploadUrl: default base matches expected dev endpoint" {
    // Guard: if someone has ZAGFORGE_API_URL set, skip the base-URL assertion.
    const maybe = std.process.getEnvVarOwned(std.testing.allocator, "ZAGFORGE_API_URL");
    if (maybe) |v| {
        std.testing.allocator.free(v);
        return; // env var is set — skip base-URL check
    } else |_| {}

    const allocator = std.testing.allocator;
    const url = try resolveUploadUrl(allocator);
    defer allocator.free(url);
    const expected = "https://zagforge-api-89960017575.us-central1.run.app/api/v1/upload";
    try std.testing.expectEqualStrings(expected, url);
}
