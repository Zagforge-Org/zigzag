# Output Refactor + LLM Report Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move report output outside the scanned source tree (to `zigzag-reports/` by default) and add `--llm-report` that generates a statically-condensed `report.llm.md` optimized for LLM ingestion.

**Architecture:** Output path resolution is extracted into `report.resolveOutputPath()` so both runner.zig and watch.zig share the same logic. LLM condensing is a pure text pipeline (comment strip → blank-line collapse → truncate) in `report.condenseContent()`. All new fields follow the existing FileConf → Config → handler → options pattern.

**Tech Stack:** Zig 0.15.2. Test runner: `zig test -ODebug -Mroot=src/root.zig --cache-dir .zig-cache --global-cache-dir ~/.cache/zig --zig-lib-dir ~/.zvm/0.15.2/lib/` (use absolute path for root). Build: `zig build`.

---

## Pre-flight

**Read before starting:**
- `src/conf/file.zig` — FileConf struct + defaultContent() pattern
- `src/cli/commands/config.zig` — Config struct, initDefault, applyFileConf, deinit pattern
- `src/cli/handlers.zig` — handler function signature pattern
- `src/cli/options.zig` — OptionHandler array
- `src/cli/commands/runner.zig` — processPath() current output path logic
- `src/cli/commands/watch.zig` — PathWatchState.init() + execWatch() output path logic
- `src/cli/commands/report.zig` — deriveJsonPath/deriveHtmlPath pattern + writeReport signature

**Test command (saves to alias `TRUN`):**
```bash
zig test -ODebug -Mroot=/home/anze/Projects/zigzag/src/root.zig --cache-dir .zig-cache --global-cache-dir /home/anze/.cache/zig --zig-lib-dir /home/anze/.zvm/0.15.2/lib/ 2>&1 | tail -20
```

**Compile-only check:**
```bash
zig build 2>&1 | head -30
```

---

## Task 1: Version Bump

**Files:**
- Modify: `src/cli/commands/config.zig:6`
- Modify: `build.zig.zon`

**Step 1: Update VERSION constant**

In `config.zig` line 6, change:
```zig
pub const VERSION = "0.12.11";
```
to:
```zig
pub const VERSION = "0.13.0";
```

**Step 2: Update build.zig.zon**

Find the `.version = "..."` field and change it to `"0.13.0"`.

**Step 3: Verify build compiles**
```bash
zig build 2>&1 | head -10
```
Expected: no errors.

**Step 4: Commit**
```bash
git add src/cli/commands/config.zig build.zig.zon
git commit -m "chore: bump version to 0.13.0 (breaking: output location)"
```

---

## Task 2: FileConf — output_dir Field

**Files:**
- Modify: `src/conf/file.zig`

**Step 1: Write the failing test** (add at end of file.zig):
```zig
test "loadFromPath parses output_dir field" {
    const allocator = std.testing.allocator;
    const tmp_path = "zztest_conf_output_dir.json";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("{\"output_dir\": \"my-reports\"}");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const result = try loadFromPath(allocator, tmp_path);
    try std.testing.expect(result != null);
    var parsed = result.?;
    defer parsed.deinit();
    try std.testing.expectEqualStrings("my-reports", parsed.value.output_dir.?);
}
```

**Step 2: Run test to verify it fails**
```bash
zig test -ODebug -Mroot=/home/anze/Projects/zigzag/src/root.zig --cache-dir .zig-cache --global-cache-dir /home/anze/.cache/zig --zig-lib-dir /home/anze/.zvm/0.15.2/lib/ 2>&1 | grep -A3 "output_dir"
```
Expected: compile error — `output_dir` not a field.

**Step 3: Add field to FileConf struct** (after `html_output` line):
```zig
output_dir: ?[]const u8 = null,
```

**Step 4: Run test to verify it passes**
```bash
zig test -ODebug -Mroot=/home/anze/Projects/zigzag/src/root.zig --cache-dir .zig-cache --global-cache-dir /home/anze/.cache/zig --zig-lib-dir /home/anze/.zvm/0.15.2/lib/ 2>&1 | tail -5
```
Expected: all tests pass.

**Step 5: Commit**
```bash
git add src/conf/file.zig
git commit -m "feat: add output_dir to FileConf"
```

---

## Task 3: Config — output_dir Fields

**Files:**
- Modify: `src/cli/commands/config.zig`

**Step 1: Write failing tests** (add after existing tests):
```zig
test "Config.initDefault has output_dir null" {
    const allocator = std.testing.allocator;
    var cfg = Config.initDefault(allocator);
    defer cfg.deinit();
    try std.testing.expect(cfg.output_dir == null);
}

test "Config.applyFileConf applies output_dir" {
    const allocator = std.testing.allocator;
    var cfg = Config.initDefault(allocator);
    defer cfg.deinit();

    const conf = FileConf{ .output_dir = "my-reports" };
    try cfg.applyFileConf(&conf, allocator);
    try std.testing.expectEqualStrings("my-reports", cfg.output_dir.?);
}

test "Config.applyFileConf leaves output_dir unchanged when FileConf field is null" {
    const allocator = std.testing.allocator;
    var cfg = Config.initDefault(allocator);
    defer cfg.deinit();

    const conf = FileConf{};
    try cfg.applyFileConf(&conf, allocator);
    try std.testing.expect(cfg.output_dir == null);
}
```

**Step 2: Run tests to verify they fail**
Expected: compile error — `output_dir` not a field on Config.

**Step 3: Add fields to Config struct** (after `html_output` line):
```zig
output_dir: ?[]u8,           // Base output directory; null means "zigzag-reports"
_output_dir_allocated: bool, // true when output_dir is heap-allocated
_output_dir_set_by_cli: bool, // true when CLI set it (prevents file conf override)
```

**Step 4: Add to initDefault()** (after `._patterns_set_by_cli = false`):
```zig
.output_dir = null,
._output_dir_allocated = false,
._output_dir_set_by_cli = false,
```

**Step 5: Add to applyFileConf()** (after the `html_output` block):
```zig
// Apply output directory (only if CLI hasn't set it)
if (!self._output_dir_set_by_cli) {
    if (conf.output_dir) |dir| {
        if (self._output_dir_allocated) {
            if (self.output_dir) |existing| self.allocator.free(existing);
        }
        self.output_dir = try allocator.dupe(u8, dir);
        self._output_dir_allocated = true;
    }
}
```

**Step 6: Add to deinit()** (after the `self.output` free block):
```zig
if (self._output_dir_allocated) {
    if (self.output_dir) |dir| self.allocator.free(dir);
}
```

**Step 7: Run tests to verify they pass**
Expected: all tests pass.

**Step 8: Commit**
```bash
git add src/cli/commands/config.zig
git commit -m "feat: add output_dir fields to Config"
```

---

## Task 4: handleOutputDir Handler + Options Entry

**Files:**
- Modify: `src/cli/handlers.zig`
- Modify: `src/cli/options.zig`

**Step 1: Write failing tests** (add to handlers.zig after the handleOutput tests):
```zig
/// handleOutputDir sets the base output directory for generated reports.
test "handleOutputDir sets output_dir" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleOutputDir(&cfg, allocator, "my-reports");
    try testing.expectEqualStrings("my-reports", cfg.output_dir.?);
    try testing.expect(cfg._output_dir_set_by_cli);
}

test "handleOutputDir trims whitespace" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleOutputDir(&cfg, allocator, "  reports/  ");
    try testing.expectEqualStrings("reports/", cfg.output_dir.?);
}

test "handleOutputDir replaces previous value" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();

    try handleOutputDir(&cfg, allocator, "first");
    try handleOutputDir(&cfg, allocator, "second");
    try testing.expectEqualStrings("second", cfg.output_dir.?);
}
```

**Step 2: Run tests to verify they fail**
Expected: compile error — `handleOutputDir` not defined.

**Step 3: Implement handleOutputDir** (add after `handleOutput` function, before `handleJson`):
```zig
/// handleOutputDir sets the base output directory for generated reports.
pub fn handleOutputDir(cfg: *Config, allocator: std.mem.Allocator, value: ?[]const u8) anyerror!void {
    if (value) |v| {
        const trimmed = std.mem.trim(u8, v, " \t\r\n");
        if (cfg._output_dir_allocated) {
            if (cfg.output_dir) |existing| allocator.free(existing);
        }
        cfg.output_dir = try allocator.dupe(u8, trimmed);
        cfg._output_dir_allocated = true;
        cfg._output_dir_set_by_cli = true;
    }
}
```

**Step 4: Add `--output-dir` to options.zig** (after the `--output` line):
```zig
.{ .name = "--output-dir", .takes_value = true, .handler = &handler.handleOutputDir },
```

**Step 5: Update help text** in `printHelp` (after the `--output` line):
```
\\  --output-dir     Base directory for report output (default: zigzag-reports)
```

**Step 6: Run tests to verify they pass**
Expected: all pass.

**Step 7: Commit**
```bash
git add src/cli/handlers.zig src/cli/options.zig
git commit -m "feat: add --output-dir handler and option"
```

---

## Task 5: Output Path Helpers in report.zig

**Files:**
- Modify: `src/cli/commands/report.zig`

These helpers centralize output path computation for both runner.zig and watch.zig.

**Step 1: Write failing tests** (add at the end of report.zig, before existing tests):
```zig
test "computeOutputSegment strips leading ./" {
    try std.testing.expectEqualStrings("src", computeOutputSegment("./src"));
    try std.testing.expectEqualStrings("src/cli", computeOutputSegment("./src/cli"));
}

test "computeOutputSegment uses basename for absolute paths" {
    try std.testing.expectEqualStrings("src", computeOutputSegment("/home/user/project/src"));
}

test "computeOutputSegment returns path unchanged when no ./ prefix" {
    try std.testing.expectEqualStrings("src", computeOutputSegment("src"));
}

test "computeOutputSegment handles bare dot" {
    try std.testing.expectEqualStrings(".", computeOutputSegment("."));
    try std.testing.expectEqualStrings(".", computeOutputSegment("./"));
}
```

**Step 2: Run tests to verify they fail**
Expected: compile error.

**Step 3: Implement computeOutputSegment** (add near the top of report.zig, after imports):
```zig
/// Compute the output directory segment for a scanned path.
/// Relative paths have "./" stripped; absolute paths use basename only.
pub fn computeOutputSegment(path: []const u8) []const u8 {
    if (std.fs.path.isAbsolute(path)) {
        return std.fs.path.basename(path);
    }
    if (std.mem.startsWith(u8, path, "./")) {
        const stripped = path[2..];
        return if (stripped.len > 0) stripped else ".";
    }
    return if (path.len > 0) path else ".";
}
```

**Step 4: Write failing test for resolveOutputPath**:
```zig
test "resolveOutputPath builds path under zigzag-reports by default" {
    const allocator = std.testing.allocator;
    var cfg = @import("config.zig").Config.initDefault(allocator);
    defer cfg.deinit();

    // Use a temp dir so makePath doesn't pollute the cwd
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const prev_cwd = std.fs.cwd();
    try tmp.dir.setAsCwd();
    defer prev_cwd.setAsCwd() catch {};

    const path = try resolveOutputPath(allocator, &cfg, "./src", "report.md");
    defer allocator.free(path);
    try std.testing.expect(std.mem.indexOf(u8, path, "zigzag-reports") != null);
    try std.testing.expect(std.mem.indexOf(u8, path, "src") != null);
    try std.testing.expect(std.mem.endsWith(u8, path, "report.md"));
}
```

**Step 5: Implement resolveOutputPath** (add after computeOutputSegment):
```zig
/// Resolve the full output file path for a given scanned path and filename.
/// Creates output directory tree if it doesn't exist.
/// Caller must free the returned slice.
pub fn resolveOutputPath(
    allocator: std.mem.Allocator,
    cfg: *const Config,
    scanned_path: []const u8,
    filename: []const u8,
) ![]u8 {
    const base_dir: []const u8 = if (cfg.output_dir) |d| d else "zigzag-reports";
    const segment = computeOutputSegment(scanned_path);
    const output_dir = try std.fs.path.join(allocator, &.{ base_dir, segment });
    defer allocator.free(output_dir);
    std.fs.cwd().makePath(output_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {}, // ok
        else => return err,
    };
    return std.fs.path.join(allocator, &.{ output_dir, filename });
}
```

**Step 6: Run tests**
Expected: all pass. Note: `resolveOutputPath` test uses `setAsCwd()` — if it hangs on WSL2, skip that specific test and mark it with `// WSL2: skip setAsCwd`.

**Step 7: Commit**
```bash
git add src/cli/commands/report.zig
git commit -m "feat: add computeOutputSegment and resolveOutputPath helpers"
```

---

## Task 6: Refactor runner.zig — New Output Path + Auto-Ignore

**Files:**
- Modify: `src/cli/commands/runner.zig`

**Step 1: Replace md_path computation** in `processPath()`.

Find lines:
```zig
const output_filename: []const u8 = if (cfg.output) |o| o else "report.md";
const md_path = try std.fs.path.join(allocator, &.{ path, output_filename });
defer allocator.free(md_path);
```

Replace with:
```zig
const output_filename: []const u8 = if (cfg.output) |o| o else "report.md";
const md_path = try report.resolveOutputPath(allocator, cfg, path, output_filename);
defer allocator.free(md_path);
```

**Step 2: Add auto-ignore for output dir** (add after `defer file_ctx.ignore_list.deinit(allocator);`, before `owned_md_path`):
```zig
// Auto-ignore the output directory to prevent scanning report artifacts
const base_output_dir: []const u8 = if (cfg.output_dir) |d| d else "zigzag-reports";
const output_dir_ignore = try allocator.dupe(u8, base_output_dir);
try file_ctx.ignore_list.append(allocator, output_dir_ignore);
```

**Step 3: Build to check for compile errors**
```bash
zig build 2>&1 | head -20
```
Expected: no errors.

**Step 4: Run full test suite**
```bash
zig test -ODebug -Mroot=/home/anze/Projects/zigzag/src/root.zig --cache-dir .zig-cache --global-cache-dir /home/anze/.cache/zig --zig-lib-dir /home/anze/.zvm/0.15.2/lib/ 2>&1 | tail -10
```
Expected: all pass. (runner.zig tests use temp dirs so they should pass.)

**Step 5: Commit**
```bash
git add src/cli/commands/runner.zig
git commit -m "feat: use resolveOutputPath in runner, auto-ignore zigzag-reports"
```

---

## Task 7: Refactor watch.zig — New Output Path

**Files:**
- Modify: `src/cli/commands/watch.zig`

**Step 1: Update PathWatchState.init()**

Find in `init()`:
```zig
const output_filename: []const u8 = if (cfg.output) |o| o else "report.md";
const md_path = try std.fs.path.join(allocator, &.{ path, output_filename });
errdefer allocator.free(md_path);
```

Replace with:
```zig
const output_filename: []const u8 = if (cfg.output) |o| o else "report.md";
const md_path = try report.resolveOutputPath(allocator, cfg, path, output_filename);
errdefer allocator.free(md_path);
```

**Step 2: Add auto-ignore for output dir** in `init()`, after `try self.file_ctx.ignore_list.append(allocator, owned_md);`:
```zig
// Auto-ignore output directory
const base_output_dir: []const u8 = if (cfg.output_dir) |d| d else "zigzag-reports";
const output_dir_ignore = try allocator.dupe(u8, base_output_dir);
try self.file_ctx.ignore_list.append(allocator, output_dir_ignore);
```

**Step 3: Update execWatch() event-loop filename filters**

The current code in the event loop filters by exact filename suffix:
```zig
if (std.mem.endsWith(u8, event.path, output_filename)) continue;
if (std.mem.endsWith(u8, event.path, json_output_filename)) continue;
if (std.mem.endsWith(u8, event.path, html_output_filename)) continue;
```

Remove those three lines and replace with a single check against the output dir:
```zig
const base_out_dir: []const u8 = if (cfg.output_dir) |d| d else "zigzag-reports";
if (std.mem.indexOf(u8, event.path, base_out_dir) != null) continue;
```

Also remove the now-unused `output_filename`, `json_output_filename`, `html_output_filename` local variables at the top of `execWatch()` (the three `const output_filename`, `json_output_filename`, `html_output_filename` blocks and their `defer allocator.free`).

**Step 4: Build to verify no errors**
```bash
zig build 2>&1 | head -20
```

**Step 5: Run test suite**
Expected: all pass.

**Step 6: Commit**
```bash
git add src/cli/commands/watch.zig
git commit -m "feat: use resolveOutputPath in watch, simplify output-dir ignore"
```

---

## Task 8: FileConf — LLM Fields

**Files:**
- Modify: `src/conf/file.zig`

**Step 1: Write failing tests** (add at end of file):
```zig
test "loadFromPath parses llm_report field" {
    const allocator = std.testing.allocator;
    const tmp_path = "zztest_conf_llm_report.json";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("{\"llm_report\": true}");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const result = try loadFromPath(allocator, tmp_path);
    var parsed = result.?;
    defer parsed.deinit();
    try std.testing.expect(parsed.value.llm_report.? == true);
}

test "loadFromPath parses llm_max_lines field" {
    const allocator = std.testing.allocator;
    const tmp_path = "zztest_conf_llm_max_lines.json";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("{\"llm_max_lines\": 200}");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const result = try loadFromPath(allocator, tmp_path);
    var parsed = result.?;
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u64, 200), parsed.value.llm_max_lines.?);
}

test "loadFromPath parses llm_description field" {
    const allocator = std.testing.allocator;
    const tmp_path = "zztest_conf_llm_desc.json";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("{\"llm_description\": \"A CLI tool\"}");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const result = try loadFromPath(allocator, tmp_path);
    var parsed = result.?;
    defer parsed.deinit();
    try std.testing.expectEqualStrings("A CLI tool", parsed.value.llm_description.?);
}
```

**Step 2: Run tests to verify they fail**

**Step 3: Add fields to FileConf** (after `output_dir`):
```zig
llm_report: ?bool = null,
llm_max_lines: ?u64 = null,
llm_description: ?[]const u8 = null,
```

**Step 4: Run tests — expect pass**

**Step 5: Commit**
```bash
git add src/conf/file.zig
git commit -m "feat: add llm_report/llm_max_lines/llm_description to FileConf"
```

---

## Task 9: Config — LLM Fields

**Files:**
- Modify: `src/cli/commands/config.zig`

**Step 1: Write failing tests**:
```zig
test "Config.initDefault has llm defaults" {
    const allocator = std.testing.allocator;
    var cfg = Config.initDefault(allocator);
    defer cfg.deinit();
    try std.testing.expect(!cfg.llm_report);
    try std.testing.expectEqual(@as(u64, 150), cfg.llm_max_lines);
    try std.testing.expect(cfg.llm_description == null);
}

test "Config.applyFileConf applies llm_report" {
    const allocator = std.testing.allocator;
    var cfg = Config.initDefault(allocator);
    defer cfg.deinit();
    const conf = FileConf{ .llm_report = true };
    try cfg.applyFileConf(&conf, allocator);
    try std.testing.expect(cfg.llm_report);
}

test "Config.applyFileConf applies llm_max_lines" {
    const allocator = std.testing.allocator;
    var cfg = Config.initDefault(allocator);
    defer cfg.deinit();
    const conf = FileConf{ .llm_max_lines = 300 };
    try cfg.applyFileConf(&conf, allocator);
    try std.testing.expectEqual(@as(u64, 300), cfg.llm_max_lines);
}

test "Config.applyFileConf applies llm_description" {
    const allocator = std.testing.allocator;
    var cfg = Config.initDefault(allocator);
    defer cfg.deinit();
    const conf = FileConf{ .llm_description = "My project" };
    try cfg.applyFileConf(&conf, allocator);
    try std.testing.expectEqualStrings("My project", cfg.llm_description.?);
}
```

**Step 2: Run tests — verify they fail**

**Step 3: Add fields to Config struct** (after `_output_dir_set_by_cli`):
```zig
llm_report: bool,              // Generate LLM-optimized condensed report
llm_max_lines: u64,            // Max lines per file before truncation (default: 150)
llm_description: ?[]u8,        // Optional project description for LLM report preamble
_llm_description_allocated: bool,
```

**Step 4: Add to initDefault()**:
```zig
.llm_report = false,
.llm_max_lines = 150,
.llm_description = null,
._llm_description_allocated = false,
```

**Step 5: Add to applyFileConf()** (after the output_dir block):
```zig
// Apply LLM report settings
if (conf.llm_report) |v| self.llm_report = v;
if (conf.llm_max_lines) |v| self.llm_max_lines = v;
if (conf.llm_description) |desc| {
    if (self._llm_description_allocated) {
        if (self.llm_description) |existing| self.allocator.free(existing);
    }
    self.llm_description = try allocator.dupe(u8, desc);
    self._llm_description_allocated = true;
}
```

**Step 6: Add to deinit()**:
```zig
if (self._llm_description_allocated) {
    if (self.llm_description) |desc| self.allocator.free(desc);
}
```

**Step 7: Run tests — expect pass**

**Step 8: Commit**
```bash
git add src/cli/commands/config.zig
git commit -m "feat: add llm_report/llm_max_lines/llm_description to Config"
```

---

## Task 10: handleLlmReport Handler + Options Entry

**Files:**
- Modify: `src/cli/handlers.zig`
- Modify: `src/cli/options.zig`

**Step 1: Write failing test** (add after handleJson tests):
```zig
test "handleLlmReport sets llm_report to true" {
    const allocator = std.testing.allocator;
    var cfg = makeTestConfig(allocator);
    defer cfg.deinit();
    try std.testing.expect(!cfg.llm_report);
    try handleLlmReport(&cfg, allocator, null);
    try std.testing.expect(cfg.llm_report);
}
```

**Step 2: Run test — verify it fails**

**Step 3: Implement handleLlmReport** (add after `handleHtml`):
```zig
/// handleLlmReport enables LLM-optimized condensed report output.
pub fn handleLlmReport(cfg: *Config, allocator: std.mem.Allocator, _: ?[]const u8) anyerror!void {
    _ = allocator;
    cfg.llm_report = true;
}
```

**Step 4: Add to options.zig** (after `--html` line):
```zig
.{ .name = "--llm-report", .takes_value = false, .handler = &handler.handleLlmReport },
```

**Step 5: Update printHelp** in handlers.zig (after `--html` line in help text):
```
\\  --llm-report     Generate a condensed LLM-optimized report (report.llm.md)
```

**Step 6: Run tests — expect pass**

**Step 7: Commit**
```bash
git add src/cli/handlers.zig src/cli/options.zig
git commit -m "feat: add --llm-report handler and option"
```

---

## Task 11: deriveLlmPath + isBoilerplate + getCommentPrefix in report.zig

**Files:**
- Modify: `src/cli/commands/report.zig`

**Step 1: Write failing tests**:
```zig
test "deriveLlmPath replaces .md extension" {
    const alloc = std.testing.allocator;
    const result = try deriveLlmPath(alloc, "zigzag-reports/src/report.md");
    defer alloc.free(result);
    try std.testing.expectEqualStrings("zigzag-reports/src/report.llm.md", result);
}

test "deriveLlmPath appends .llm.md when no .md extension" {
    const alloc = std.testing.allocator;
    const result = try deriveLlmPath(alloc, "zigzag-reports/src/report");
    defer alloc.free(result);
    try std.testing.expectEqualStrings("zigzag-reports/src/report.llm.md", result);
}

test "isBoilerplate detects lock files" {
    try std.testing.expect(isBoilerplate("package-lock.json"));
    try std.testing.expect(isBoilerplate("yarn.lock"));
    try std.testing.expect(isBoilerplate("Cargo.lock"));
    try std.testing.expect(isBoilerplate("go.sum"));
}

test "isBoilerplate detects minified files" {
    try std.testing.expect(isBoilerplate("app.min.js"));
    try std.testing.expect(isBoilerplate("styles.min.css"));
}

test "isBoilerplate returns false for normal files" {
    try std.testing.expect(!isBoilerplate("main.zig"));
    try std.testing.expect(!isBoilerplate("config.go"));
}

test "getCommentPrefix returns correct prefix" {
    try std.testing.expectEqualStrings("//", getCommentPrefix(".zig").?);
    try std.testing.expectEqualStrings("//", getCommentPrefix(".js").?);
    try std.testing.expectEqualStrings("#", getCommentPrefix(".py").?);
    try std.testing.expectEqualStrings("#", getCommentPrefix(".sh").?);
    try std.testing.expectEqualStrings("--", getCommentPrefix(".sql").?);
}

test "getCommentPrefix returns null for unknown extension" {
    try std.testing.expect(getCommentPrefix(".xyz") == null);
    try std.testing.expect(getCommentPrefix("") == null);
}
```

**Step 2: Run tests — verify they fail**

**Step 3: Implement deriveLlmPath** (add after `deriveHtmlPath`):
```zig
/// Derive an LLM-optimized report path from the markdown path.
pub fn deriveLlmPath(allocator: std.mem.Allocator, md_path: []const u8) ![]u8 {
    if (std.mem.endsWith(u8, md_path, ".md")) {
        return std.fmt.allocPrint(allocator, "{s}.llm.md", .{md_path[0 .. md_path.len - 3]});
    }
    return std.fmt.allocPrint(allocator, "{s}.llm.md", .{md_path});
}
```

**Step 4: Implement isBoilerplate** (add after deriveLlmPath):
```zig
const BOILERPLATE_BASENAMES = [_][]const u8{
    "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "Cargo.lock",
    "go.sum", "poetry.lock", "Gemfile.lock", "composer.lock", "bun.lockb",
};
const BOILERPLATE_SUFFIXES = [_][]const u8{ ".min.js", ".min.css", ".pb.go" };

pub fn isBoilerplate(path: []const u8) bool {
    const basename = std.fs.path.basename(path);
    for (BOILERPLATE_BASENAMES) |b| {
        if (std.mem.eql(u8, basename, b)) return true;
    }
    for (BOILERPLATE_SUFFIXES) |suffix| {
        if (std.mem.endsWith(u8, basename, suffix)) return true;
    }
    return false;
}
```

**Step 5: Implement getCommentPrefix** (add after isBoilerplate):
```zig
pub fn getCommentPrefix(extension: []const u8) ?[]const u8 {
    const ext = if (extension.len > 0 and extension[0] == '.') extension[1..] else extension;
    const map = [_]struct { ext: []const u8, prefix: []const u8 }{
        .{ .ext = "zig", .prefix = "//" }, .{ .ext = "js", .prefix = "//" },
        .{ .ext = "ts", .prefix = "//" },  .{ .ext = "jsx", .prefix = "//" },
        .{ .ext = "tsx", .prefix = "//" }, .{ .ext = "rs", .prefix = "//" },
        .{ .ext = "go", .prefix = "//" },  .{ .ext = "c", .prefix = "//" },
        .{ .ext = "cpp", .prefix = "//" }, .{ .ext = "h", .prefix = "//" },
        .{ .ext = "hpp", .prefix = "//" }, .{ .ext = "java", .prefix = "//" },
        .{ .ext = "cs", .prefix = "//" },  .{ .ext = "swift", .prefix = "//" },
        .{ .ext = "kt", .prefix = "//" },  .{ .ext = "py", .prefix = "#" },
        .{ .ext = "sh", .prefix = "#" },   .{ .ext = "bash", .prefix = "#" },
        .{ .ext = "zsh", .prefix = "#" },  .{ .ext = "rb", .prefix = "#" },
        .{ .ext = "yaml", .prefix = "#" }, .{ .ext = "yml", .prefix = "#" },
        .{ .ext = "toml", .prefix = "#" }, .{ .ext = "r", .prefix = "#" },
        .{ .ext = "sql", .prefix = "--" }, .{ .ext = "lua", .prefix = "--" },
    };
    for (map) |entry| {
        if (std.mem.eql(u8, ext, entry.ext)) return entry.prefix;
    }
    return null;
}
```

**Step 6: Run tests — expect pass**

**Step 7: Commit**
```bash
git add src/cli/commands/report.zig
git commit -m "feat: add deriveLlmPath, isBoilerplate, getCommentPrefix helpers"
```

---

## Task 12: condenseContent in report.zig

**Files:**
- Modify: `src/cli/commands/report.zig`

**Step 1: Write failing tests**:
```zig
test "condenseContent strips single-line comments" {
    const alloc = std.testing.allocator;
    const input = "// this is a comment\nconst x = 1;\n// another comment\n";
    const result = try condenseContent(input, 1000, ".zig", alloc);
    defer alloc.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "// this is") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "const x = 1;") != null);
}

test "condenseContent collapses consecutive blank lines" {
    const alloc = std.testing.allocator;
    const input = "a\n\n\n\nb\n";
    const result = try condenseContent(input, 1000, ".zig", alloc);
    defer alloc.free(result);
    // Should have at most one blank line between a and b
    try std.testing.expect(std.mem.indexOf(u8, result, "a\n\nb\n") != null or
        std.mem.indexOf(u8, result, "a\n\nb") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\n\n\n") == null);
}

test "condenseContent truncates files over max_lines with correct omission count" {
    const alloc = std.testing.allocator;
    // Build a 200-line file
    var buf = std.ArrayList(u8).init(alloc);
    defer buf.deinit();
    for (0..200) |i| {
        try buf.writer().print("line{d}\n", .{i});
    }
    const result = try condenseContent(buf.items, 80, "", alloc);
    defer alloc.free(result);
    // Should contain omission marker
    try std.testing.expect(std.mem.indexOf(u8, result, "lines omitted") != null);
    // Should NOT contain all 200 lines
    try std.testing.expect(std.mem.indexOf(u8, result, "line199") != null); // last line present
    try std.testing.expect(std.mem.indexOf(u8, result, "line0") != null);   // first line present
}

test "condenseContent returns full content when under max_lines" {
    const alloc = std.testing.allocator;
    const input = "a\nb\nc\n";
    const result = try condenseContent(input, 1000, ".zig", alloc);
    defer alloc.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "omitted") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "a") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "b") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "c") != null);
}

test "condenseContent does not strip comments for unknown extension" {
    const alloc = std.testing.allocator;
    const input = "// keep this\ndata\n";
    const result = try condenseContent(input, 1000, ".xyz", alloc);
    defer alloc.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "// keep this") != null);
}
```

**Step 2: Run tests — verify they fail**

**Step 3: Implement condenseContent** (add after getCommentPrefix):
```zig
const CONDENSE_FIRST_N: usize = 60;
const CONDENSE_LAST_M: usize = 20;

/// Condense file content for LLM consumption.
/// - Strips single-line comments (language-aware, extension-based)
/// - Collapses consecutive blank lines to max 1
/// - Truncates files over max_lines: shows first 60 + last 20 lines with omission marker
/// Returns owned slice; caller must free.
pub fn condenseContent(
    content: []const u8,
    max_lines: u64,
    extension: []const u8,
    allocator: std.mem.Allocator,
) ![]u8 {
    const comment_prefix = getCommentPrefix(extension);

    var cleaned = std.ArrayList([]const u8).init(allocator);
    defer cleaned.deinit();

    var prev_blank = false;
    var it = std.mem.splitScalar(u8, content, '\n');
    while (it.next()) |raw_line| {
        const trimmed = std.mem.trim(u8, raw_line, " \t\r");

        // Skip pure single-line comment lines
        if (comment_prefix) |prefix| {
            if (std.mem.startsWith(u8, trimmed, prefix)) continue;
        }

        // Collapse consecutive blank lines
        const is_blank = trimmed.len == 0;
        if (is_blank) {
            if (prev_blank) continue;
            prev_blank = true;
        } else {
            prev_blank = false;
        }

        try cleaned.append(raw_line);
    }

    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    const n = cleaned.items.len;
    const limit: usize = @intCast(max_lines);

    if (n > limit) {
        const show_first = @min(CONDENSE_FIRST_N, limit);
        const show_last = @min(CONDENSE_LAST_M, limit -| show_first);
        const omitted = n - show_first - show_last;

        for (cleaned.items[0..show_first]) |line| {
            try result.appendSlice(line);
            try result.append('\n');
        }
        try result.writer().print("// [{d} lines omitted]\n", .{omitted});
        if (show_last > 0) {
            for (cleaned.items[n - show_last ..]) |line| {
                try result.appendSlice(line);
                try result.append('\n');
            }
        }
    } else {
        for (cleaned.items) |line| {
            try result.appendSlice(line);
            try result.append('\n');
        }
    }

    return result.toOwnedSlice();
}
```

**Step 4: Run tests — expect pass**

**Step 5: Commit**
```bash
git add src/cli/commands/report.zig
git commit -m "feat: add condenseContent for LLM report generation"
```

---

## Task 13: writeLlmReport in report.zig

**Files:**
- Modify: `src/cli/commands/report.zig`

**Step 1: Write failing test**:
```zig
test "writeLlmReport creates file with correct sections" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Build minimal file_entries
    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();
    const content = try alloc.dupe(u8, "const x = 1;\n");
    defer alloc.free(content);
    try file_entries.put("src/main.zig", JobEntry{
        .path = "src/main.zig",
        .content = content,
        .size = 13,
        .mtime = 0,
        .extension = ".zig",
        .line_count = 1,
    });

    var binary_entries = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries.deinit();

    var cfg = @import("config.zig").Config.initDefault(alloc);
    defer cfg.deinit();

    const llm_path = try std.fs.path.join(alloc, &.{ ".", "zztest_llm_report.md" });
    defer alloc.free(llm_path);
    defer std.fs.cwd().deleteFile(llm_path) catch {};

    try writeLlmReport(&file_entries, &binary_entries, llm_path, "src", cfg, alloc);

    const written = try std.fs.cwd().readFileAlloc(alloc, llm_path, 1 << 20);
    defer alloc.free(written);

    try std.testing.expect(std.mem.indexOf(u8, written, "LLM Context") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "Statistics") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "File Index") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "Source") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "src/main.zig") != null);
}

test "writeLlmReport skips boilerplate files" {
    const alloc = std.testing.allocator;

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();
    const lock_content = try alloc.dupe(u8, "{\"lockfileVersion\": 3}\n");
    defer alloc.free(lock_content);
    try file_entries.put("package-lock.json", JobEntry{
        .path = "package-lock.json",
        .content = lock_content,
        .size = 23,
        .mtime = 0,
        .extension = ".json",
        .line_count = 1,
    });

    var binary_entries = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries.deinit();

    var cfg = @import("config.zig").Config.initDefault(alloc);
    defer cfg.deinit();

    const llm_path = "zztest_llm_boilerplate.md";
    defer std.fs.cwd().deleteFile(llm_path) catch {};

    try writeLlmReport(&file_entries, &binary_entries, llm_path, ".", cfg, alloc);

    const written = try std.fs.cwd().readFileAlloc(alloc, llm_path, 1 << 20);
    defer alloc.free(written);

    try std.testing.expect(std.mem.indexOf(u8, written, "package-lock.json") == null);
}

test "writeLlmReport includes llm_description when set" {
    const alloc = std.testing.allocator;

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();

    var binary_entries = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries.deinit();

    var cfg = @import("config.zig").Config.initDefault(alloc);
    defer cfg.deinit();
    cfg.llm_description = @constCast("My awesome CLI tool");

    const llm_path = "zztest_llm_desc.md";
    defer std.fs.cwd().deleteFile(llm_path) catch {};

    try writeLlmReport(&file_entries, &binary_entries, llm_path, ".", cfg, alloc);

    const written = try std.fs.cwd().readFileAlloc(alloc, llm_path, 1 << 20);
    defer alloc.free(written);

    try std.testing.expect(std.mem.indexOf(u8, written, "My awesome CLI tool") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "Project Description") != null);
}
```

**Step 2: Run tests — verify they fail**

**Step 3: Implement writeLlmReport** (add after `writeHtmlReport`):
```zig
/// Write an LLM-optimized condensed report.
pub fn writeLlmReport(
    file_entries: *const std.StringHashMap(JobEntry),
    binary_entries: *const std.StringHashMap(BinaryEntry),
    llm_path: []const u8,
    root_path: []const u8,
    cfg: Config,
    allocator: std.mem.Allocator,
) !void {
    const output_filename = std.fs.path.basename(llm_path);
    std.log.info("Building {s} for {s}...", .{ output_filename, root_path });

    var llm_file = try std.fs.cwd().createFile(llm_path, .{ .truncate = true });
    defer llm_file.close();

    var bw = std.io.bufferedWriter(llm_file.writer());
    const w = bw.writer();

    // Date header
    const now = std.time.timestamp();
    const local_now = if (cfg.timezone_offset) |offset| now + offset else now;
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(local_now) };
    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    // Sort entries
    var sorted = std.ArrayList(JobEntry).init(allocator);
    defer sorted.deinit();
    var it = file_entries.iterator();
    while (it.next()) |e| try sorted.append(e.value_ptr.*);
    std.mem.sort(JobEntry, sorted.items, {}, struct {
        fn lt(_: void, a: JobEntry, b: JobEntry) bool {
            return std.mem.lessThan(u8, a.path, b.path);
        }
    }.lt);

    // Compute statistics
    var source_count: u32 = 0;
    var boilerplate_skipped: u32 = 0;
    var original_lines: u64 = 0;
    var condensed_lines: u64 = 0;
    var lang_map = std.StringHashMap(u32).init(allocator);
    defer lang_map.deinit();

    for (sorted.items) |e| {
        if (isBoilerplate(e.path)) { boilerplate_skipped += 1; continue; }
        source_count += 1;
        original_lines += e.line_count;
        condensed_lines += @min(e.line_count, cfg.llm_max_lines);
        const lang = e.getLanguage();
        if (lang.len > 0) {
            const gop = try lang_map.getOrPut(lang);
            if (!gop.found_existing) gop.value_ptr.* = 0;
            gop.value_ptr.* += 1;
        }
    }

    const reduction_pct: u64 = if (original_lines > 0)
        (original_lines - @min(condensed_lines, original_lines)) * 100 / original_lines
    else 0;

    // === Header ===
    try w.print("# LLM Context: {s}\n", .{root_path});
    try w.writeAll("> This report is condensed for LLM ingestion. " ++
        "The full human-readable report is available at report.md.\n");
    try w.print("> ZigZag v{s} · {d}-{d:0>2}-{d:0>2}\n\n", .{
        VERSION,
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
    });

    // === Project Description ===
    if (cfg.llm_description) |desc| {
        try w.writeAll("## Project Description\n\n");
        try w.print("{s}\n\n", .{desc});
    }

    // === Statistics ===
    try w.writeAll("## Statistics\n\n");
    try w.print("- Source files: {d}  |  Binary files: {d}  |  Boilerplate skipped: {d}\n",
        .{ source_count, binary_entries.count(), boilerplate_skipped });
    try w.print("- Original lines: {d}  →  Condensed: ~{d}  ({d}% reduction)\n\n",
        .{ original_lines, condensed_lines, reduction_pct });

    // === File Index ===
    try w.writeAll("## File Index\n\n");
    for (sorted.items) |e| {
        if (isBoilerplate(e.path)) continue;
        if (e.line_count > cfg.llm_max_lines) {
            try w.print("- {s} (condensed — {d} of {d} lines shown)\n",
                .{ e.path, cfg.llm_max_lines, e.line_count });
        } else {
            try w.print("- {s} ({d} lines, full)\n", .{ e.path, e.line_count });
        }
    }
    try w.writeByte('\n');

    // === Source ===
    try w.writeAll("## Source\n\n");
    for (sorted.items) |e| {
        if (isBoilerplate(e.path)) continue;

        const is_truncated = e.line_count > cfg.llm_max_lines;
        if (is_truncated) {
            try w.print("### {s} *(condensed — {d} of {d} lines shown)*\n\n",
                .{ e.path, cfg.llm_max_lines, e.line_count });
        } else {
            try w.print("### {s}\n\n", .{e.path});
        }

        const lang = e.getLanguage();
        try w.print("```{s}\n", .{lang});

        const condensed = try condenseContent(e.content, cfg.llm_max_lines, e.extension, allocator);
        defer allocator.free(condensed);
        try w.writeAll(condensed);
        if (condensed.len == 0 or condensed[condensed.len - 1] != '\n') {
            try w.writeByte('\n');
        }
        try w.writeAll("```\n\n");
    }

    try bw.flush();
}
```

**Step 4: Run tests — expect pass**

**Step 5: Commit**
```bash
git add src/cli/commands/report.zig
git commit -m "feat: implement writeLlmReport with static condensing pipeline"
```

---

## Task 14: Wire LLM Report in runner.zig and watch.zig

**Files:**
- Modify: `src/cli/commands/runner.zig`
- Modify: `src/cli/commands/watch.zig`

**Step 1: Add llm-report to runner.zig ignore list**

In `processPath()`, after the `html_ignore` block:
```zig
if (cfg.llm_report) {
    const llm_ignore = try report.deriveLlmPath(allocator, md_path);
    try file_ctx.ignore_list.append(allocator, llm_ignore);
}
```

**Step 2: Add llm-report write call in runner.zig**

After the `html_output` block at the end of `processPath()`:
```zig
if (cfg.llm_report) {
    const llm_path = try report.deriveLlmPath(allocator, md_path);
    defer allocator.free(llm_path);
    try report.writeLlmReport(&file_entries, &binary_entries, llm_path, path, cfg, allocator);
}
```

**Step 3: Add llm-report to watch.zig ignore list**

In `PathWatchState.init()`, after the `html_ignore_path` block:
```zig
if (cfg.llm_report) {
    const llm_ignore_path = try report.deriveLlmPath(allocator, md_path);
    try self.file_ctx.ignore_list.append(allocator, llm_ignore_path);
}
```

**Step 4: Add llm-report write call in watch.zig debounce flush**

In `execWatch()`, in the debounce flush loop (after the `html_output` block):
```zig
if (cfg.llm_report) {
    const llm_path = report.deriveLlmPath(allocator, state.md_path) catch null;
    if (llm_path) |lp| {
        defer allocator.free(lp);
        report.writeLlmReport(&state.file_entries, &state.binary_entries, lp, state.root_path, cfg, allocator) catch |err| {
            std.log.err("Failed to write LLM report for '{s}': {s}", .{ state.root_path, @errorName(err) });
        };
    }
}
```

Also add the same in the initial scan write section (after the `html_output` initial write block):
```zig
if (cfg.llm_report) {
    const llm_path = report.deriveLlmPath(allocator, state.md_path) catch null;
    if (llm_path) |lp| {
        defer allocator.free(lp);
        report.writeLlmReport(&state.file_entries, &state.binary_entries, lp, state.root_path, cfg, allocator) catch |err| {
            std.log.err("Failed to write initial LLM report for '{s}': {s}", .{ state.root_path, @errorName(err) });
        };
    }
}
```

**Step 5: Build**
```bash
zig build 2>&1 | head -20
```
Expected: no errors.

**Step 6: Run full test suite**
```bash
zig test -ODebug -Mroot=/home/anze/Projects/zigzag/src/root.zig --cache-dir .zig-cache --global-cache-dir /home/anze/.cache/zig --zig-lib-dir /home/anze/.zvm/0.15.2/lib/ 2>&1 | tail -10
```
Expected: all pass.

**Step 7: Commit**
```bash
git add src/cli/commands/runner.zig src/cli/commands/watch.zig
git commit -m "feat: wire --llm-report into runner and watch mode"
```

---

## Task 15: Update defaultContent() in file.zig

**Files:**
- Modify: `src/conf/file.zig`

**Step 1: Write failing test** (the existing `defaultContent is valid parseable JSON` test will need to be checked — ensure new fields parse):
```zig
test "defaultContent includes output_dir and llm fields" {
    const allocator = std.testing.allocator;
    const content = defaultContent();
    const parsed = try std.json.parseFromSlice(FileConf, allocator, content, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    // output_dir defaults to null (not set) - that's fine, it should parse
    try std.testing.expect(parsed.value.llm_report != null);
    try std.testing.expect(parsed.value.llm_report.? == false);
}
```

**Step 2: Run test — verify it fails**

**Step 3: Update defaultContent()** to include new fields:
```zig
pub fn defaultContent() []const u8 {
    return
    \\{
    \\  "paths": [],
    \\  "ignore_patterns": [],
    \\  "skip_cache": false,
    \\  "skip_git": false,
    \\  "small_threshold": 1048576,
    \\  "mmap_threshold": 16777216,
    \\  "timezone": null,
    \\  "output": "report.md",
    \\  "output_dir": "zigzag-reports",
    \\  "watch": false,
    \\  "json_output": false,
    \\  "html_output": false,
    \\  "llm_report": false,
    \\  "llm_max_lines": 150,
    \\  "llm_description": null
    \\}
    \\
    ;
}
```

**Step 4: Run all tests — expect pass** (including the existing `defaultContent is valid parseable JSON` test).

**Step 5: Commit**
```bash
git add src/conf/file.zig
git commit -m "feat: update defaultContent with output_dir and llm fields"
```

---

## Task 16: Final Verification

**Step 1: Full test suite**
```bash
zig test -ODebug -Mroot=/home/anze/Projects/zigzag/src/root.zig --cache-dir .zig-cache --global-cache-dir /home/anze/.cache/zig --zig-lib-dir /home/anze/.zvm/0.15.2/lib/ 2>&1
```
Expected: 0 failures.

**Step 2: Release build**
```bash
zig build -Doptimize=ReleaseFast 2>&1
```
Expected: no errors.

**Step 3: Smoke test — run on the project itself**
```bash
./zig-out/bin/zigzag --path ./src --llm-report 2>&1 | head -20
ls zigzag-reports/src/
```
Expected: `zigzag-reports/src/report.md` and `zigzag-reports/src/report.llm.md` both exist.

**Step 4: Verify --output-dir override**
```bash
./zig-out/bin/zigzag --path ./src --output-dir /tmp/test-reports 2>&1 | head -5
ls /tmp/test-reports/src/
```
Expected: `report.md` in `/tmp/test-reports/src/`.

**Step 5: Final commit if any fixes needed, then done**
