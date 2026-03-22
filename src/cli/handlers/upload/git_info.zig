const std = @import("std");

pub const GitInfo = struct {
    commit_sha: []const u8,
    branch: []const u8,
    repo_full_name: []const u8, // "org/repo"
    org_slug: []const u8, // slice of repo_full_name — do not free separately

    pub fn deinit(self: *const GitInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.commit_sha);
        allocator.free(self.branch);
        allocator.free(self.repo_full_name);
        // org_slug is a slice of repo_full_name — freed above
    }
};

/// Run a git command and return duped, whitespace-trimmed stdout. Caller owns result.
fn runGit(allocator: std.mem.Allocator, argv: []const []const u8) ![]u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
    allocator.free(result.stderr);
    defer allocator.free(result.stdout);
    switch (result.term) {
        .Exited => |code| if (code != 0) return error.GitCommandFailed,
        else => return error.GitCommandFailed,
    }
    const trimmed = std.mem.trim(u8, result.stdout, &std.ascii.whitespace);
    return allocator.dupe(u8, trimmed);
}

/// Extract "org/repo" from a git remote URL. Caller owns the returned slice.
///
/// Supported formats:
///   https://github.com/org/repo.git
///   https://github.com/org/repo
///   git@github.com:org/repo.git
///   git@github.com:org/repo
pub fn parseRepoFullName(allocator: std.mem.Allocator, remote_url: []const u8) ![]const u8 {
    var url = remote_url;

    // Strip trailing .git
    if (std.mem.endsWith(u8, url, ".git")) url = url[0 .. url.len - 4];

    // HTTPS: https://github.com/org/repo
    if (std.mem.startsWith(u8, url, "https://") or std.mem.startsWith(u8, url, "http://")) {
        const after_scheme = (std.mem.indexOf(u8, url, "//") orelse return error.InvalidRemoteUrl) + 2;
        const slash = std.mem.indexOfPos(u8, url, after_scheme, "/") orelse return error.InvalidRemoteUrl;
        return allocator.dupe(u8, url[slash + 1 ..]);
    }

    // SSH: git@github.com:org/repo
    if (std.mem.indexOfScalar(u8, url, ':')) |colon| {
        return allocator.dupe(u8, url[colon + 1 ..]);
    }

    return error.InvalidRemoteUrl;
}

/// Collect git metadata for the current working directory.
pub fn getGitInfo(allocator: std.mem.Allocator) !GitInfo {
    const commit_sha = try runGit(allocator, &.{ "git", "rev-parse", "HEAD" });
    errdefer allocator.free(commit_sha);

    const branch = runGit(allocator, &.{ "git", "rev-parse", "--abbrev-ref", "HEAD" }) catch
        try allocator.dupe(u8, "unknown");
    errdefer allocator.free(branch);

    const remote_url = runGit(allocator, &.{ "git", "remote", "get-url", "origin" }) catch
        try allocator.dupe(u8, "");
    defer allocator.free(remote_url);

    const repo_full_name = if (remote_url.len > 0)
        parseRepoFullName(allocator, remote_url) catch try allocator.dupe(u8, "unknown/unknown")
    else
        try allocator.dupe(u8, "unknown/unknown");
    errdefer allocator.free(repo_full_name);

    const slash = std.mem.indexOfScalar(u8, repo_full_name, '/') orelse repo_full_name.len;
    const org_slug = repo_full_name[0..slash];

    return GitInfo{
        .commit_sha = commit_sha,
        .branch = branch,
        .repo_full_name = repo_full_name,
        .org_slug = org_slug,
    };
}
