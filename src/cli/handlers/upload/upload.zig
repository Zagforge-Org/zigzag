const std = @import("std");
const Config = @import("../../commands/config/config.zig").Config;
const ScanResult = @import("../../commands/runner/scan.zig").ScanResult;
const GitInfo = @import("./git_info.zig").GitInfo;
const getGitInfo = @import("./git_info.zig").getGitInfo;
const lg = @import("../../../utils/utils.zig");

/// Default API base URL. Override at runtime with ZAGFORGE_API_URL env var.
/// Changing this constant is the only code change needed when switching to
/// the production endpoint.
const DEFAULT_API_BASE = "https://zagforge-api-89960017575.us-central1.run.app";
const UPLOAD_PATH = "/api/v1/upload";

/// Return the full upload endpoint URL. Checks ZAGFORGE_API_URL env var for the
/// base (e.g. "https://api.zagforge.com"), then falls back to DEFAULT_API_BASE.
/// Caller owns the returned slice.
pub fn resolveUploadUrl(allocator: std.mem.Allocator) ![]const u8 {
    const base = std.process.getEnvVarOwned(allocator, "ZAGFORGE_API_URL") catch
        try allocator.dupe(u8, DEFAULT_API_BASE);
    defer allocator.free(base);
    // Strip any trailing slash so concatenation is consistent.
    const base_clean = std.mem.trimRight(u8, base, "/");
    return std.fmt.allocPrint(allocator, "{s}{s}", .{ base_clean, UPLOAD_PATH });
}

/// Discover the Zagforge API key. Checks ZAGFORGE_API_KEY env var first, then
/// ~/.zagforge/credentials. Caller owns the returned slice.
pub fn getApiKey(allocator: std.mem.Allocator) ![]const u8 {
    // 1. Environment variable
    if (std.process.getEnvVarOwned(allocator, "ZAGFORGE_API_KEY")) |key| {
        return key;
    } else |_| {}

    // 2. ~/.zagforge/credentials  (ZAGFORGE_API_KEY=zf_pk_...)
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch return error.MissingApiKey;
    defer allocator.free(home);

    const cred_path = try std.fs.path.join(allocator, &.{ home, ".zagforge", "credentials" });
    defer allocator.free(cred_path);

    const contents = std.fs.cwd().readFileAlloc(allocator, cred_path, 4096) catch return error.MissingApiKey;
    defer allocator.free(contents);

    return parseApiKeyFromCredentials(allocator, contents) orelse error.MissingApiKey;
}

/// Extract the API key value from credentials file contents. Returns null if the
/// ZAGFORGE_API_KEY= line is absent. Split out for testability.
pub fn parseApiKeyFromCredentials(allocator: std.mem.Allocator, contents: []const u8) ?[]const u8 {
    const prefix = "ZAGFORGE_API_KEY=";
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (std.mem.startsWith(u8, trimmed, prefix)) {
            return allocator.dupe(u8, trimmed[prefix.len..]) catch null;
        }
    }
    return null;
}

/// Compute the git blob SHA-1 for a file's content and write 40 hex chars into `out`.
/// SHA-1 is computed over "blob {size}\0{content}" — identical to what git stores.
pub fn gitBlobSha(content: []const u8, out: *[40]u8) void {
    var sha1 = std.crypto.hash.Sha1.init(.{});
    var prefix_buf: [32]u8 = undefined;
    const prefix = std.fmt.bufPrint(&prefix_buf, "blob {d}\x00", .{content.len}) catch unreachable;
    sha1.update(prefix);
    sha1.update(content);
    var digest: [std.crypto.hash.Sha1.digest_length]u8 = undefined;
    sha1.final(&digest);
    const hex = std.fmt.bytesToHex(digest, .lower);
    @memcpy(out, &hex);
}

/// Build and POST the snapshot JSON for a single scan result.
fn uploadResult(
    result: *const ScanResult,
    cfg: *const Config,
    api_key: []const u8,
    git: GitInfo,
    allocator: std.mem.Allocator,
) !void {
    // generated_at in ISO-8601 UTC
    const ts_secs: u64 = @intCast(@divFloor(std.time.nanoTimestamp(), std.time.ns_per_s));
    const epoch = std.time.epoch.EpochSeconds{ .secs = ts_secs };
    const yd = epoch.getEpochDay().calculateYearDay();
    const md = yd.calculateMonthDay();
    const ds = epoch.getDaySeconds();
    const generated_at = try std.fmt.allocPrint(
        allocator,
        "{d}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z",
        .{
            yd.year,
            md.month.numeric(),
            md.day_index + 1,
            ds.getHoursIntoDay(),
            ds.getMinutesIntoHour(),
            ds.getSecondsIntoMinute(),
        },
    );
    defer allocator.free(generated_at);

    // Aggregate total lines across all source files
    var total_lines: u64 = 0;
    {
        var it = result.file_entries.iterator();
        while (it.next()) |entry| total_lines += entry.value_ptr.line_count;
    }

    // Build JSON payload
    var aw: std.io.Writer.Allocating = .init(allocator);
    defer aw.deinit();

    var ws: std.json.Stringify = .{ .writer = &aw.writer, .options = .{ .whitespace = .minified } };
    try ws.beginObject();

    try ws.objectField("org_slug");
    try ws.write(git.org_slug);

    try ws.objectField("repo_full_name");
    try ws.write(git.repo_full_name);

    try ws.objectField("commit_sha");
    try ws.write(git.commit_sha);

    try ws.objectField("branch");
    try ws.write(git.branch);

    try ws.objectField("metadata_snapshot");
    try ws.beginObject();

    try ws.objectField("snapshot_version");
    try ws.write(2);

    try ws.objectField("zigzag_version");
    try ws.write(cfg.version);

    try ws.objectField("commit_sha");
    try ws.write(git.commit_sha);

    try ws.objectField("branch");
    try ws.write(git.branch);

    try ws.objectField("generated_at");
    try ws.write(generated_at);

    try ws.objectField("summary");
    try ws.beginObject();
    try ws.objectField("source_files");
    try ws.write(result.file_entries.count());
    try ws.objectField("total_lines");
    try ws.write(total_lines);
    try ws.endObject();

    try ws.objectField("file_tree");
    try ws.beginArray();
    {
        var it = result.file_entries.iterator();
        while (it.next()) |entry| {
            const e = entry.value_ptr;
            var sha_hex: [40]u8 = undefined;
            gitBlobSha(e.content, &sha_hex);
            try ws.beginObject();
            try ws.objectField("path");
            try ws.write(e.path);
            try ws.objectField("language");
            try ws.write(e.getLanguage());
            try ws.objectField("lines");
            try ws.write(e.line_count);
            try ws.objectField("sha");
            try ws.write(&sha_hex);
            try ws.endObject();
        }
    }
    try ws.endArray(); // file_tree

    try ws.endObject(); // metadata_snapshot
    try ws.endObject(); // root

    const body = aw.written();

    const upload_url = try resolveUploadUrl(allocator);
    defer allocator.free(upload_url);

    const auth_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{api_key});
    defer allocator.free(auth_header);

    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    const fetch_result = try client.fetch(.{
        .location = .{ .url = upload_url },
        .extra_headers = &.{
            .{ .name = "Authorization", .value = auth_header },
            .{ .name = "Content-Type", .value = "application/json" },
        },
        .payload = body,
    });

    const source_files = result.file_entries.count();
    if (fetch_result.status == .created) {
        lg.printSuccess("Snapshot uploaded ({d} files, {d} lines)", .{ source_files, total_lines });
        lg.printSuccess("View at: https://cloud.zagforge.com/repos/{s}", .{git.repo_full_name});
    } else {
        lg.printError("Upload failed: HTTP {d}", .{@intFromEnum(fetch_result.status)});
        return error.UploadFailed;
    }
}

const UPLOAD_TIMEOUT_NS: i128 = 30 * std.time.ns_per_s;

const UploadTask = struct {
    result: *const ScanResult,
    cfg: *const Config,
    api_key: []const u8,
    git: GitInfo,
    /// Arena backed by page_allocator so GPA never sees upload-internal allocations.
    /// On success: deinit() then destroy task. On timeout: leak both (detached thread).
    arena: std.heap.ArenaAllocator,
    err: ?anyerror = null,
    completed: std.atomic.Value(bool) = .{ .raw = false },
};

fn runUploadTask(task: *UploadTask) void {
    uploadResult(task.result, task.cfg, task.api_key, task.git, task.arena.allocator()) catch |e| {
        task.err = e;
    };
    task.completed.store(true, .release);
}

/// Called by the runner after all reports are written. POSTs a snapshot for each
/// successfully scanned path.
pub fn performUpload(
    results: []const ScanResult,
    cfg: *const Config,
    allocator: std.mem.Allocator,
) !void {
    if (results.len == 0) return;

    const api_key = getApiKey(allocator) catch {
        lg.printError("--upload requires ZAGFORGE_API_KEY.", .{});
        lg.printError("Export the variable or add it to ~/.zagforge/credentials.", .{});
        lg.printError("Get a token at: https://cloud.zagforge.com/settings/tokens", .{});
        return error.MissingApiKey;
    };
    defer allocator.free(api_key);

    const git = getGitInfo(allocator) catch |err| {
        lg.printError("Could not read git info: {s}", .{@errorName(err)});
        return err;
    };
    defer git.deinit(allocator);

    for (results) |*result| {
        // Allocate task + arena on page_allocator so GPA never tracks upload-internal
        // memory. On timeout both are intentionally leaked (detached thread still holds them).
        const task = try std.heap.page_allocator.create(UploadTask);
        task.* = .{
            .result = result,
            .cfg = cfg,
            .api_key = api_key,
            .git = git,
            .arena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
        };

        const thread = std.Thread.spawn(.{}, runUploadTask, .{task}) catch |err| {
            std.heap.page_allocator.destroy(task);
            lg.printError("Upload failed for {s}: {s}", .{ result.root_path, @errorName(err) });
            continue;
        };

        const deadline: i128 = std.time.nanoTimestamp() + UPLOAD_TIMEOUT_NS;
        var timed_out = false;
        while (!task.completed.load(.acquire)) {
            if (std.time.nanoTimestamp() > deadline) {
                timed_out = true;
                break;
            }
            std.Thread.sleep(10 * std.time.ns_per_ms);
        }

        if (timed_out) {
            lg.printError("Upload timed out for {s} (30s exceeded)", .{result.root_path});
            thread.detach();
            // task is intentionally leaked — detached thread still holds a reference to it
        } else {
            thread.join();
            if (task.err) |err| {
                lg.printError("Upload failed for {s}: {s}", .{ result.root_path, @errorName(err) });
            }
            task.arena.deinit();
            std.heap.page_allocator.destroy(task);
        }
    }
}
