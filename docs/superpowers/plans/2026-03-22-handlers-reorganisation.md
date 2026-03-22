# Handlers Reorganisation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganise `src/cli/handlers/` from a flat 24-file directory into four responsibility-scoped subfolders (`flags/`, `display/`, `upload/`, `init/`, `internal/`), and move all inline tests to sibling `_test.zig` files.

**Architecture:** All 24 handler source files are moved to their subfolder with updated relative import paths. Inline `test` blocks and test-only imports are stripped from each source file and placed in a sibling `_test.zig`. External callers (`flags.zig`, `main.zig`, `runner.zig`, `root.zig`) are updated atomically after all new files exist, then old files are deleted.

**Tech Stack:** Zig 0.15.2. No new dependencies. Test command: `make test`. Build command: `zig build`.

---

## File Map

### New files created
```
src/cli/handlers/internal/test_config.zig
src/cli/handlers/flags/{chunk_size,html,ignore,json,llm_report,log,mmap,no_watch,open,output,output_dir,path,port,skip_cache,small,timezone,upload,watch}.zig
src/cli/handlers/flags/{chunk_size,html,ignore,json,llm_report,log,mmap,no_watch,open,output,output_dir,path,port,skip_cache,small,timezone,upload,watch}_test.zig
src/cli/handlers/display/{help,logo,version}.zig
src/cli/handlers/display/{help,version}_test.zig
src/cli/handlers/upload/{upload,git_info}.zig
src/cli/handlers/upload/{upload,git_info}_test.zig
src/cli/handlers/init/init.zig
src/cli/handlers/init/init_test.zig
```

### Old files deleted
```
src/cli/handlers/{chunk_size,html,ignore,json,llm_report,log,mmap,no_watch,open,output,output_dir,path,port,skip_cache,small,timezone,upload,watch}.zig
src/cli/handlers/{help,logo,version}.zig
src/cli/handlers/{init,git_info,test_config}.zig
```

### Modified
```
src/cli/flags.zig           — 20 import paths updated
src/main.zig                — 2 import paths updated (logo, init)
src/cli/commands/runner.zig — 1 import path updated (upload)
src/root.zig                — 21 handler source imports → 23 _test.zig imports
```

---

## Execution order rationale

New files are created first (Tasks 1–7). External callers are switched in one atomic step (Task 8), then old files are deleted (Task 9). Between Tasks 1–7 and Task 8 the build is always green because old files still exist. After Task 8, old files are unreferenced; Task 9 deletes them and the build is verified.

---

## Task 1: Pre-flight and directory setup

**Files:** no source changes

- [ ] **Step 1: Verify build.zig has no handler references**

```bash
grep -r "handlers" /home/anze/Projects/zigzag/build.zig
```

Expected: no output (build.zig uses `root.zig` as test root, does not enumerate handler files).

- [ ] **Step 2: Create all subdirectories**

```bash
mkdir -p src/cli/handlers/flags
mkdir -p src/cli/handlers/display
mkdir -p src/cli/handlers/upload
mkdir -p src/cli/handlers/init
mkdir -p src/cli/handlers/internal
```

- [ ] **Step 3: Verify build still passes**

```bash
zig build
```
Expected: clean build.

---

## Task 2: Create `internal/test_config.zig`

**Files:**
- Create: `src/cli/handlers/internal/test_config.zig`

The only change from the original is one extra `../` in the Config import path.

- [ ] **Step 1: Create the file**

```zig
// src/cli/handlers/internal/test_config.zig
const std = @import("std");
const Config = @import("../../commands/config/config.zig").Config;

pub fn makeTestConfig(allocator: std.mem.Allocator) Config {
    return Config.default(allocator);
}
```

- [ ] **Step 2: Verify build**

```bash
zig build
```
Expected: clean (old `test_config.zig` still exists; this is an additional file).

---

## Task 3: Create `flags/` source files

**Pattern rule:** Every flags/ source file gains one extra `../` on every import, loses all `test` blocks, and loses `const testing = std.testing` and `const makeTestConfig = ...` import lines.

**Files:** Create all 18 files listed below. Do NOT delete old files yet.

- [ ] **Step 1: Create `flags/no_watch.zig` (full example — follow this pattern for all)**

```zig
// src/cli/handlers/flags/no_watch.zig
const std = @import("std");
const Config = @import("../../commands/config/config.zig").Config;

/// handleNoWatch disables watch mode, overriding any file config setting.
pub fn handleNoWatch(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    cfg.watch = false;
    cfg._no_watch_set_by_cli = true;
}
```

- [ ] **Step 2: Create all remaining `flags/` source files**

Apply the same pattern (strip tests + update imports) to each of these. The only import that changes is `../commands/...` → `../../commands/...`. Files with a `parseTimezoneStr` import get `../../commands/config/timezone/timezone.zig`.

| New file | Handler fn | Extra import changes |
|---|---|---|
| `flags/chunk_size.zig` | `handleChunkSize` | none |
| `flags/html.zig` | `handleHtml` | none |
| `flags/ignore.zig` | `handleIgnores` | none |
| `flags/json.zig` | `handleJson` | none |
| `flags/llm_report.zig` | `handleLlmReport` | none |
| `flags/log.zig` | `handleLog` | none |
| `flags/mmap.zig` | `handleMmap` | none |
| `flags/open.zig` | `handleOpen` | none |
| `flags/output.zig` | `handleOutput` | none |
| `flags/output_dir.zig` | `handleOutputDir` | none |
| `flags/path.zig` | `handlePaths` | none |
| `flags/port.zig` | `handlePort` | none |
| `flags/skip_cache.zig` | `handleSkipCache` | none |
| `flags/small.zig` | `handleSmall` | none |
| `flags/timezone.zig` | `handleTimezone` | `../../commands/config/timezone/timezone.zig` |
| `flags/watch.zig` | `handleWatch` | none |

- [ ] **Step 3: Create `flags/upload.zig` (the thin flag setter — NOT the HTTP logic)**

```zig
// src/cli/handlers/flags/upload.zig
const std = @import("std");
const Config = @import("../../commands/config/config.zig").Config;

pub fn handleUpload(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    cfg.upload = true;
}
```

- [ ] **Step 4: Verify build**

```bash
zig build
```
Expected: clean (old files still exist alongside new ones).

---

## Task 4: Create `flags/` test files

**Pattern rule:** Each `_test.zig` imports the handler function from `./handler_name.zig` and `makeTestConfig` from `../internal/test_config.zig`. No `pub` declarations.

**Files:** Create all 18 `_test.zig` files.

- [ ] **Step 1: Create `flags/no_watch_test.zig` (full example)**

```zig
// src/cli/handlers/flags/no_watch_test.zig
const std = @import("std");
const handleNoWatch = @import("./no_watch.zig").handleNoWatch;
const makeTestConfig = @import("../internal/test_config.zig").makeTestConfig;

test "handleNoWatch disables watch mode" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    cfg.watch = true;
    try std.testing.expect(cfg.watch);
    try handleNoWatch(&cfg, allocator, null);
    try std.testing.expect(!cfg.watch);
    try std.testing.expect(cfg._no_watch_set_by_cli);
}
```

- [ ] **Step 2: Create `flags/upload_test.zig` (only the two flag-setter tests)**

```zig
// src/cli/handlers/flags/upload_test.zig
const std = @import("std");
const handleUpload = @import("./upload.zig").handleUpload;
const makeTestConfig = @import("../internal/test_config.zig").makeTestConfig;

test "handleUpload sets cfg.upload to true" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try std.testing.expect(!cfg.upload);
    try handleUpload(&cfg, allocator, null);
    try std.testing.expect(cfg.upload);
}

test "handleUpload ignores value argument" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleUpload(&cfg, allocator, "unexpected");
    try std.testing.expect(cfg.upload);
}
```

- [ ] **Step 3: Create the remaining 16 `flags/_test.zig` files**

Copy the test blocks verbatim from the matching old source file, update the handler import to `@import("./name.zig").handlerFn`, and set `makeTestConfig` to `@import("../internal/test_config.zig").makeTestConfig`. The test body content does not change.

Files: `chunk_size_test.zig`, `html_test.zig`, `ignore_test.zig`, `json_test.zig`, `llm_report_test.zig`, `log_test.zig`, `mmap_test.zig`, `open_test.zig`, `output_test.zig`, `output_dir_test.zig`, `path_test.zig`, `port_test.zig`, `skip_cache_test.zig`, `small_test.zig`, `timezone_test.zig`, `watch_test.zig`.

- [ ] **Step 4: Verify build**

```bash
zig build
```
Expected: clean.

---

## Task 5: Create `display/` files

**Files:**
- Create: `src/cli/handlers/display/help.zig`
- Create: `src/cli/handlers/display/help_test.zig`
- Create: `src/cli/handlers/display/logo.zig`
- Create: `src/cli/handlers/display/version.zig`
- Create: `src/cli/handlers/display/version_test.zig`

- [ ] **Step 1: Create `display/help.zig`**

Same content as old `help.zig` minus test blocks. Import paths: `../../commands/config/config.zig`, `../../../fs/stdout.zig`.

```zig
// src/cli/handlers/display/help.zig
const std = @import("std");
const Config = @import("../../commands/config/config.zig").Config;
const stdoutPrint = @import("../../../fs/stdout.zig").stdoutPrint;

pub fn printHelp(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = cfg;
    _ = allocator;
    _ = value;
    try stdoutPrint(
        \\Usage: zigzag [COMMAND] [OPTIONS]
        \\
        \\Commands:
        \\  init            Initialize a new project (creates zig.conf.json)
        \\  run             Run using zig.conf.json (flags override config file)
        \\  bench           Run with per-phase timing instrumentation
        \\
        \\Options:
        \\  --help           Print this help message
        \\  --paths          One or more paths, comma-separated (e.g. --paths ./src,./lib)
        \\  --version        Print version information
        \\  --ignores        One or more ignore patterns, comma-separated (e.g. --ignores "*.png,*.jpg")
        \\                   Note: paths/patterns containing a comma must be set in zig.conf.json
        \\  --skip-git       Skip git operations
        \\  --skip-cache     Skip cache operations
        \\  --strategy       Print strategy
        \\  --small          Small threshold in bytes (default: 1 MiB)
        \\  --mmap           Mmap threshold in bytes (default: 16 MiB)
        \\  --timezone       Timezone offset from UTC (e.g., +1, -5, +5:30)
        \\  --output         Output filename (default: report.md)
        \\  --output-dir     Base directory for report output (default: zigzag-reports)
        \\  --json           Generate a JSON report alongside the markdown report
        \\  --html           Generate an HTML report alongside the markdown report
        \\  --watch          Watch for file changes and regenerate output
        \\  --llm-report     Generate a condensed LLM-optimized report (report.llm.md)
        \\  --chunk-size <N> Split LLM report into chunks of N bytes (e.g. 500k, 2m)
        \\
        \\Ignore Pattern Examples:
        \\  --ignores "*.png"             Ignore all PNG files
        \\  --ignores "test.txt"          Ignore specific file
        \\  --ignores "node_modules"      Ignore directory
        \\  --ignores "*.svg,*.jpg"       Multiple patterns
        \\
        \\Auto-ignored items:
        \\  - Binary files (images, executables, archives, etc.)
        \\  - node_modules, .git, .cache, __pycache__, etc.
        \\
        \\Examples:
        \\  zigzag run
        \\  zigzag run --paths ./src --ignores "*.test.zig"
        \\  zigzag run --watch
        \\  zigzag --paths ./project1,./project2
        \\  zigzag --paths ./src --timezone +1
        \\
    , .{});
}
```

- [ ] **Step 2: Create `display/help_test.zig`**

```zig
// src/cli/handlers/display/help_test.zig
const std = @import("std");
const printHelp = @import("./help.zig").printHelp;
const makeTestConfig = @import("../internal/test_config.zig").makeTestConfig;

test "printHelp runs without error" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();
    try printHelp(&cfg, allocator, null);
}
```

- [ ] **Step 3: Create `display/logo.zig`**

Same content as old `logo.zig` — only import paths change (`../../../utils/utils.zig`, `../../../fs/stdout.zig`). No tests to strip.

```zig
// src/cli/handlers/display/logo.zig
const colors = @import("../../../utils/utils.zig");
const stdoutPrint = @import("../../../fs/stdout.zig").stdoutPrint;

pub const ascii_logo =
    \\
    \\
    \\$$$$$$$$\ $$\                 $$$$$$$$\
    \\____$$  |\__|                \____$$  |
    \\    $$  / $$\  $$$$$$\            $$  / $$$$$$\   $$$$$$\
    \\   $$  /  $$ |$$  __$$\          $$  /  \____$$\ $$  __$$\
    \\  $$  /   $$ |$$ /  $$ |        $$  /   $$$$$$$ |$$ /  $$ |
    \\ $$  /    $$ |$$ |  $$ |       $$  /   $$  __$$ |$$ |  $$ |
    \\$$$$$$$$\ $$ |\$$$$$$$ |      $$$$$$$$\\$$$$$$$ |\$$$$$$$ |
    \\________|\__| \____$$ |      \________|\_______| \____$$ |
    \\              $$\   $$ |                         $$\   $$ |
    \\              \$$$$$$  |                         \$$$$$$  |
    \\               \______/                           \______/
    \\
    \\
;

pub fn printAsciiLogo() anyerror!void {
    try stdoutPrint("{s}{s}{s}", .{
        colors.colorCode(colors.Color.Yellow),
        ascii_logo,
        colors.colorCode(colors.Color.Reset),
    });
}
```

- [ ] **Step 4: Create `display/version.zig`**

```zig
// src/cli/handlers/display/version.zig
const std = @import("std");
const Config = @import("../../commands/config/config.zig").Config;
const stdoutPrint = @import("../../../fs/stdout.zig").stdoutPrint;
pub const VERSION = @import("../../commands/config/config.zig").VERSION;

pub fn printVersion(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    _ = allocator;
    _ = value;
    try stdoutPrint(
        \\version {s}
        \\
    , .{
        cfg.version,
    });
}
```

- [ ] **Step 5: Create `display/version_test.zig`**

```zig
// src/cli/handlers/display/version_test.zig
const std = @import("std");
const printVersion = @import("./version.zig").printVersion;
const VERSION = @import("./version.zig").VERSION;
const makeTestConfig = @import("../internal/test_config.zig").makeTestConfig;

test "printVersion should print version information" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();
    try std.testing.expectEqualStrings(VERSION, cfg.version);
}
```

- [ ] **Step 6: Verify build**

```bash
zig build
```
Expected: clean.

---

## Task 6: Create `upload/` files

The current `src/cli/handlers/upload.zig` contains both the flag setter (`handleUpload`) and the HTTP networking logic. Here we create the networking file only — `handleUpload` now lives in `flags/upload.zig` (Task 3).

**Files:**
- Create: `src/cli/handlers/upload/upload.zig`
- Create: `src/cli/handlers/upload/upload_test.zig`
- Create: `src/cli/handlers/upload/git_info.zig`
- Create: `src/cli/handlers/upload/git_info_test.zig`

- [ ] **Step 1: Create `upload/git_info.zig`**

Same content as old `src/cli/handlers/git_info.zig`. Only `std` is imported — no path changes needed. Strip the inline test blocks (they move to `git_info_test.zig`).

```zig
// src/cli/handlers/upload/git_info.zig
const std = @import("std");

pub const GitInfo = struct {
    commit_sha: []const u8,
    branch: []const u8,
    repo_full_name: []const u8,
    org_slug: []const u8,

    pub fn deinit(self: *const GitInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.commit_sha);
        allocator.free(self.branch);
        allocator.free(self.repo_full_name);
    }
};

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

pub fn parseRepoFullName(allocator: std.mem.Allocator, remote_url: []const u8) ![]const u8 {
    var url = remote_url;
    if (std.mem.endsWith(u8, url, ".git")) url = url[0 .. url.len - 4];

    if (std.mem.startsWith(u8, url, "https://") or std.mem.startsWith(u8, url, "http://")) {
        const after_scheme = (std.mem.indexOf(u8, url, "//") orelse return error.InvalidRemoteUrl) + 2;
        const slash = std.mem.indexOfPos(u8, url, after_scheme, "/") orelse return error.InvalidRemoteUrl;
        return allocator.dupe(u8, url[slash + 1 ..]);
    }

    if (std.mem.indexOfScalar(u8, url, ':')) |colon| {
        return allocator.dupe(u8, url[colon + 1 ..]);
    }

    return error.InvalidRemoteUrl;
}

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
```

- [ ] **Step 2: Create `upload/git_info_test.zig`**

Copy all test blocks verbatim from old `src/cli/handlers/git_info.zig`.

```zig
// src/cli/handlers/upload/git_info_test.zig
const std = @import("std");
const parseRepoFullName = @import("./git_info.zig").parseRepoFullName;

test "parseRepoFullName: HTTPS with .git suffix" {
    const allocator = std.testing.allocator;
    const name = try parseRepoFullName(allocator, "https://github.com/acme/myrepo.git");
    defer allocator.free(name);
    try std.testing.expectEqualStrings("acme/myrepo", name);
}

test "parseRepoFullName: HTTPS without .git suffix" {
    const allocator = std.testing.allocator;
    const name = try parseRepoFullName(allocator, "https://github.com/acme/myrepo");
    defer allocator.free(name);
    try std.testing.expectEqualStrings("acme/myrepo", name);
}

test "parseRepoFullName: HTTP (non-TLS) URL" {
    const allocator = std.testing.allocator;
    const name = try parseRepoFullName(allocator, "http://github.com/acme/myrepo.git");
    defer allocator.free(name);
    try std.testing.expectEqualStrings("acme/myrepo", name);
}

test "parseRepoFullName: SSH with .git suffix" {
    const allocator = std.testing.allocator;
    const name = try parseRepoFullName(allocator, "git@github.com:acme/myrepo.git");
    defer allocator.free(name);
    try std.testing.expectEqualStrings("acme/myrepo", name);
}

test "parseRepoFullName: SSH without .git suffix" {
    const allocator = std.testing.allocator;
    const name = try parseRepoFullName(allocator, "git@github.com:acme/myrepo");
    defer allocator.free(name);
    try std.testing.expectEqualStrings("acme/myrepo", name);
}

test "parseRepoFullName: org_slug derived correctly" {
    const allocator = std.testing.allocator;
    const name = try parseRepoFullName(allocator, "https://github.com/zagforge/zigzag.git");
    defer allocator.free(name);
    const slash = std.mem.indexOfScalar(u8, name, '/') orelse name.len;
    try std.testing.expectEqualStrings("zagforge", name[0..slash]);
    try std.testing.expectEqualStrings("zigzag", name[slash + 1 ..]);
}

test "parseRepoFullName: HTTPS missing path returns error" {
    const allocator = std.testing.allocator;
    const result = parseRepoFullName(allocator, "https://github.com");
    try std.testing.expectError(error.InvalidRemoteUrl, result);
}
```

- [ ] **Step 3: Create `upload/upload.zig`**

Copy the current `src/cli/handlers/upload.zig`, remove `handleUpload` and its test blocks (those moved to `flags/`), and update the following import paths:

| Old | New |
|---|---|
| `../commands/config/config.zig` | `../../commands/config/config.zig` |
| `../commands/runner/scan.zig` | `../../commands/runner/scan.zig` |
| `./git_info.zig` | `./git_info.zig` (unchanged — still a sibling) |
| `../../utils/utils.zig` | `../../../utils/utils.zig` |
| `./test_config.zig` | removed (no tests in source file) |

Also remove: `const makeTestConfig = ...` and the `handleUpload` function and its two tests.

- [ ] **Step 4: Create `upload/upload_test.zig`**

Copy all test blocks from old `upload.zig` EXCEPT the two `handleUpload` tests (those are in `flags/upload_test.zig`).

```zig
// src/cli/handlers/upload/upload_test.zig
const std = @import("std");
const gitBlobSha = @import("./upload.zig").gitBlobSha;
const parseApiKeyFromCredentials = @import("./upload.zig").parseApiKeyFromCredentials;
const resolveUploadUrl = @import("./upload.zig").resolveUploadUrl;

test "gitBlobSha: empty content matches git empty-blob SHA" {
    var out: [40]u8 = undefined;
    gitBlobSha("", &out);
    try std.testing.expectEqualStrings("e69de29bb2d1d6434b8b29ae775ad8c2e48c5391", &out);
}

test "gitBlobSha: 'hello\\n' matches known git SHA" {
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
    const url = try resolveUploadUrl(allocator);
    defer allocator.free(url);
    try std.testing.expect(std.mem.endsWith(u8, url, "/api/v1/upload"));
}

test "resolveUploadUrl: default base matches expected dev endpoint" {
    const maybe = std.process.getEnvVarOwned(std.testing.allocator, "ZAGFORGE_API_URL");
    if (maybe) |v| {
        std.testing.allocator.free(v);
        return;
    } else |_| {}
    const allocator = std.testing.allocator;
    const url = try resolveUploadUrl(allocator);
    defer allocator.free(url);
    const expected = "https://zagforge-api-89960017575.us-central1.run.app/api/v1/upload";
    try std.testing.expectEqualStrings(expected, url);
}
```

- [ ] **Step 5: Verify build**

```bash
zig build
```
Expected: clean.

---

## Task 7: Create `init/` files

**Files:**
- Create: `src/cli/handlers/init/init.zig`
- Create: `src/cli/handlers/init/init_test.zig`

- [ ] **Step 1: Create `init/init.zig`**

Copy old `init.zig`, strip test blocks, update import paths (each gains one `../`):

| Old | New |
|---|---|
| `../../conf/file.zig` | `../../../conf/file.zig` |
| `../../utils/utils.zig` | `../../../utils/utils.zig` |

```zig
// src/cli/handlers/init/init.zig
const std = @import("std");

const DEFAULT_CONF_FILENAME = @import("../../../conf/file.zig").DEFAULT_CONF_FILENAME;
const FileConf = @import("../../../conf/file.zig").FileConf;
const lg = @import("../../../utils/utils.zig");

pub fn handleInit(allocator: std.mem.Allocator, dir: std.fs.Dir) anyerror!void {
    const full_path = try std.fs.path.join(allocator, &[_][]const u8{ ".", DEFAULT_CONF_FILENAME });

    const file = dir.createFile(DEFAULT_CONF_FILENAME, .{
        .read = true,
        .exclusive = true,
    }) catch |err| switch (err) {
        error.PathAlreadyExists => {
            const content = try FileConf.read(allocator, full_path) orelse FileConf.default();
            if (FileConf.isEmpty(content)) {
                try FileConf.writeDefaultConfig(full_path);
                return;
            }
            lg.printWarn("{s} already exists", .{DEFAULT_CONF_FILENAME});
            return;
        },
        else => return err,
    };
    defer file.close();

    try FileConf.writeDefaultConfig(full_path);
    lg.printSuccess("Created {s}", .{DEFAULT_CONF_FILENAME});
}
```

- [ ] **Step 2: Create `init/init_test.zig`**

Copy the two test blocks verbatim from old `init.zig`.

```zig
// src/cli/handlers/init/init_test.zig
const std = @import("std");
const testing = std.testing;
const handleInit = @import("./init.zig").handleInit;
const FileConf = @import("../../../conf/file.zig").FileConf;
const DEFAULT_CONF_FILENAME = @import("../../../conf/file.zig").DEFAULT_CONF_FILENAME;

test "handleInit creates file with default content" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try handleInit(allocator, tmp_dir.dir);

    const content = try tmp_dir.dir.readFileAlloc(allocator, DEFAULT_CONF_FILENAME, 1 << 20);
    defer allocator.free(content);

    try testing.expect(content.len > 0);

    const parsed = try std.json.parseFromSlice(
        FileConf,
        allocator,
        content,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    try testing.expect(parsed.value.watch.? == false);
    try testing.expectEqualStrings("report.md", parsed.value.output.?);
}

test "handleInit does not overwrite existing file" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    {
        const f = try tmp_dir.dir.createFile(DEFAULT_CONF_FILENAME, .{});
        defer f.close();
        try f.writeAll("{\"watch\": true}");
    }

    try handleInit(allocator, tmp_dir.dir);

    const content = try tmp_dir.dir.readFileAlloc(allocator, DEFAULT_CONF_FILENAME, 1 << 20);
    defer allocator.free(content);

    try testing.expectEqualStrings("{\"watch\": true}", content);
}
```

- [ ] **Step 3: Verify build**

```bash
zig build
```
Expected: clean.

---

## Task 8: Switch all external callers and update `root.zig` (atomic)

All new files now exist. Switch every caller to the new paths, then delete old files. Do all edits in this task before running any verification — they are interdependent.

**Files modified:**
- `src/cli/flags.zig`
- `src/main.zig`
- `src/cli/commands/runner.zig`
- `src/root.zig`

- [ ] **Step 1: Replace all of `src/cli/flags.zig`**

```zig
const std = @import("std");
const Config = @import("./commands/config/config.zig").Config;

const versionHandler = @import("./handlers/display/version.zig").printVersion;
const helpHandler = @import("./handlers/display/help.zig").printHelp;
const skipCacheHandler = @import("./handlers/flags/skip_cache.zig").handleSkipCache;
const smallHandler = @import("./handlers/flags/small.zig").handleSmall;
const mmapHandler = @import("./handlers/flags/mmap.zig").handleMmap;
const pathHandler = @import("./handlers/flags/path.zig").handlePaths;
const ignoreHandler = @import("./handlers/flags/ignore.zig").handleIgnores;
const timezoneHandler = @import("./handlers/flags/timezone.zig").handleTimezone;
const watchHandler = @import("./handlers/flags/watch.zig").handleWatch;
const noWatchHandler = @import("./handlers/flags/no_watch.zig").handleNoWatch;
const outputHandler = @import("./handlers/flags/output.zig").handleOutput;
const outputDirHandler = @import("./handlers/flags/output_dir.zig").handleOutputDir;
const jsonHandler = @import("./handlers/flags/json.zig").handleJson;
const htmlHandler = @import("./handlers/flags/html.zig").handleHtml;
const llmReportHandler = @import("./handlers/flags/llm_report.zig").handleLlmReport;
const chunkSizeHandler = @import("./handlers/flags/chunk_size.zig").handleChunkSize;
const portHandler = @import("./handlers/flags/port.zig").handlePort;
const logHandler = @import("./handlers/flags/log.zig").handleLog;
const openHandler = @import("./handlers/flags/open.zig").handleOpen;
const uploadHandler = @import("./handlers/flags/upload.zig").handleUpload;

///  FlagsHandler represents a command-line flag.
pub const FlagsHandler = struct {
    name: []const u8,
    takes_value: bool,
    handler: *const fn (*Config, std.mem.Allocator, ?[]const u8) anyerror!void,
};

pub const flags = [_]FlagsHandler{
    .{ .name = "--version", .takes_value = false, .handler = &versionHandler },
    .{ .name = "--help", .takes_value = false, .handler = &helpHandler },
    .{ .name = "--skip-cache", .takes_value = false, .handler = &skipCacheHandler },
    .{ .name = "--small", .takes_value = true, .handler = &smallHandler },
    .{ .name = "--mmap", .takes_value = true, .handler = &mmapHandler },
    .{ .name = "--paths", .takes_value = true, .handler = &pathHandler },
    .{ .name = "--ignores", .takes_value = true, .handler = &ignoreHandler },
    .{ .name = "--timezone", .takes_value = true, .handler = &timezoneHandler },
    .{ .name = "--watch", .takes_value = false, .handler = &watchHandler },
    .{ .name = "--no-watch", .takes_value = false, .handler = &noWatchHandler },
    .{ .name = "--output", .takes_value = true, .handler = &outputHandler },
    .{ .name = "--output-dir", .takes_value = true, .handler = &outputDirHandler },
    .{ .name = "--json", .takes_value = false, .handler = &jsonHandler },
    .{ .name = "--html", .takes_value = false, .handler = &htmlHandler },
    .{ .name = "--llm-report", .takes_value = false, .handler = &llmReportHandler },
    .{ .name = "--chunk-size", .takes_value = true, .handler = &chunkSizeHandler },
    .{ .name = "--port", .takes_value = true, .handler = &portHandler },
    .{ .name = "--log", .takes_value = false, .handler = &logHandler },
    .{ .name = "--open", .takes_value = false, .handler = &openHandler },
    .{ .name = "--upload", .takes_value = false, .handler = &uploadHandler },
};
```

- [ ] **Step 2: Update the two imports in `src/main.zig`**

```zig
// old:
const printAsciiLogo = @import("./cli/handlers/logo.zig").printAsciiLogo;
const initHandler = @import("./cli/handlers/init.zig").handleInit;

// new:
const printAsciiLogo = @import("./cli/handlers/display/logo.zig").printAsciiLogo;
const initHandler = @import("./cli/handlers/init/init.zig").handleInit;
```

- [ ] **Step 3: Update the one import in `src/cli/commands/runner.zig`**

```zig
// old:
const upload_mod = @import("../handlers/upload.zig");

// new:
const upload_mod = @import("../handlers/upload/upload.zig");
```

- [ ] **Step 4: Replace the handler section of `src/root.zig`**

Remove these 21 lines (they relied on inline test discovery):
```zig
_ = @import("./cli/handlers/version.zig");
_ = @import("./cli/handlers/help.zig");
_ = @import("./cli/handlers/skip_cache.zig");
_ = @import("./cli/handlers/small.zig");
_ = @import("./cli/handlers/mmap.zig");
_ = @import("./cli/handlers/path.zig");
_ = @import("./cli/handlers/ignore.zig");
_ = @import("./cli/handlers/timezone.zig");
_ = @import("./cli/handlers/watch.zig");
_ = @import("./cli/handlers/no_watch.zig");
_ = @import("./cli/handlers/output.zig");
_ = @import("./cli/handlers/output_dir.zig");
_ = @import("./cli/handlers/json.zig");
_ = @import("./cli/handlers/html.zig");
_ = @import("./cli/handlers/llm_report.zig");
_ = @import("./cli/handlers/chunk_size.zig");
_ = @import("./cli/handlers/port.zig");
_ = @import("./cli/handlers/log.zig");
_ = @import("./cli/handlers/open.zig");
_ = @import("./cli/handlers/git_info.zig");
_ = @import("./cli/handlers/upload.zig");
```

Replace with these 23 lines:
```zig
    // handler tests — flags/
    _ = @import("./cli/handlers/flags/chunk_size_test.zig");
    _ = @import("./cli/handlers/flags/html_test.zig");
    _ = @import("./cli/handlers/flags/ignore_test.zig");
    _ = @import("./cli/handlers/flags/json_test.zig");
    _ = @import("./cli/handlers/flags/llm_report_test.zig");
    _ = @import("./cli/handlers/flags/log_test.zig");
    _ = @import("./cli/handlers/flags/mmap_test.zig");
    _ = @import("./cli/handlers/flags/no_watch_test.zig");
    _ = @import("./cli/handlers/flags/open_test.zig");
    _ = @import("./cli/handlers/flags/output_test.zig");
    _ = @import("./cli/handlers/flags/output_dir_test.zig");
    _ = @import("./cli/handlers/flags/path_test.zig");
    _ = @import("./cli/handlers/flags/port_test.zig");
    _ = @import("./cli/handlers/flags/skip_cache_test.zig");
    _ = @import("./cli/handlers/flags/small_test.zig");
    _ = @import("./cli/handlers/flags/timezone_test.zig");
    _ = @import("./cli/handlers/flags/upload_test.zig");
    _ = @import("./cli/handlers/flags/watch_test.zig");
    // handler tests — display/
    _ = @import("./cli/handlers/display/help_test.zig");
    _ = @import("./cli/handlers/display/version_test.zig");
    // handler tests — upload/
    _ = @import("./cli/handlers/upload/upload_test.zig");
    _ = @import("./cli/handlers/upload/git_info_test.zig");
    // handler tests — init/ (previously undiscovered — adds 2 tests)
    _ = @import("./cli/handlers/init/init_test.zig");
```

---

## Task 9: Delete old files and verify

- [ ] **Step 1: Delete old flat handler files**

```bash
cd src/cli/handlers
rm chunk_size.zig html.zig ignore.zig json.zig llm_report.zig log.zig mmap.zig \
   no_watch.zig open.zig output.zig output_dir.zig path.zig port.zig \
   skip_cache.zig small.zig timezone.zig watch.zig upload.zig \
   help.zig logo.zig version.zig init.zig git_info.zig test_config.zig
```

- [ ] **Step 2: Build**

```bash
cd /home/anze/Projects/zigzag && zig build
```
Expected: clean build, no errors.

- [ ] **Step 3: Run tests**

```bash
make test
```
Expected: all tests pass. Test count increases by 2 vs baseline (init_test.zig was previously undiscovered). Final count: **295 passed**.

- [ ] **Step 4: Confirm no test blocks remain in handler source files**

```bash
grep -r "^test " src/cli/handlers --include="*.zig" | grep -v "_test.zig"
```
Expected: no output.

- [ ] **Step 5: Confirm no handler source file imports `std.testing` or `makeTestConfig`**

```bash
grep -r "std\.testing\|makeTestConfig" src/cli/handlers --include="*.zig" | grep -v "_test.zig"
```
Expected: no output.
