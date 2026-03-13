# bench Subcommand Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `zigzag bench` subcommand that runs the full scan-and-report pipeline with per-phase nanosecond timing and prints a formatted breakdown table.

**Architecture:** `BenchResult` struct lives in `runner.zig`; `runner.exec()` and `writePathReports()` gain an optional `?*BenchResult` param that is filled when non-null (zero cost when null); `bench.zig` orchestrates the run and prints the table; `main.zig` dispatches the `bench` subcommand before `is_serve_command`.

**Tech Stack:** Zig 0.15.2, `std.time.nanoTimestamp`, existing `lg` stderr/colors infra.

---

## Chunk 1: BenchResult struct + runner instrumentation

### Task 1: Add `BenchResult`, `nsElapsed`, `fileSizeOf` to `runner.zig`

**Files:**
- Modify: `src/cli/commands/runner.zig` (insert after line 16: `const Logger = lg.Logger;`)

- [ ] **Step 1: Insert the struct and helpers**

Add after `const Logger = lg.Logger;` (line 16):

```zig
/// Per-phase timing and context stats collected during a benchmarked run.
/// All ns fields accumulate across multiple paths with +=.
pub const BenchResult = struct {
    scan_ns:       u64 = 0,
    aggregate_ns:  u64 = 0,
    write_md_ns:   u64 = 0,
    write_json_ns: u64 = 0,
    write_html_ns: u64 = 0,
    write_llm_ns:  u64 = 0,

    files_total:   usize = 0,
    files_source:  usize = 0,
    files_binary:  usize = 0,
    files_ignored: usize = 0,
    md_bytes:      u64 = 0,
    json_bytes:    u64 = 0,
    html_bytes:    u64 = 0,
    llm_bytes:     u64 = 0,
};

/// Nanoseconds elapsed since `start` (from nanoTimestamp). Clamped to 0.
inline fn nsElapsed(start: i128) u64 {
    const delta = std.time.nanoTimestamp() - start;
    return @intCast(@max(0, delta));
}

/// File size in bytes, or 0 on error.
fn fileSizeOf(path: []const u8) u64 {
    const stat = std.fs.cwd().statFile(path) catch return 0;
    return stat.size;
}
```

- [ ] **Step 2: Run tests — expect no failures**

```bash
cd /home/anze/Projects/zigzag && make test 2>&1 | tail -5
```
Expected: `207 passed; 1 skipped; 0 failed.`

- [ ] **Step 3: Commit**

```bash
cd /home/anze/Projects/zigzag && git add src/cli/commands/runner.zig && git commit -m "feat: add BenchResult struct and timing helpers to runner.zig"
```

---

### Task 2: Instrument `exec()` with scan-phase timing and update callers

**Files:**
- Modify: `src/cli/commands/runner.zig` — `exec()` signature (line 287) + scan loop (lines 324–345)
- Modify: `src/main.zig` — two `runner.exec` call sites (lines 90, 147)

- [ ] **Step 1: Update `exec()` signature**

Change line 287 from:
```zig
pub fn exec(cfg: *const Config, cache: ?*CacheImpl, allocator: std.mem.Allocator) !void {
```
to:
```zig
pub fn exec(cfg: *const Config, cache: ?*CacheImpl, allocator: std.mem.Allocator, bench: ?*BenchResult) !void {
```

- [ ] **Step 2: Add scan timing inside the path loop**

In `exec()`, the scan loop starts at `for (cfg.paths.items) |path| {`. Change:
```zig
    for (cfg.paths.items) |path| {
        const result = scanPath(cfg, cache, path, &pool, allocator, logger) catch |err| {
```
to:
```zig
    for (cfg.paths.items) |path| {
        const t_scan = std.time.nanoTimestamp();
        const result = scanPath(cfg, cache, path, &pool, allocator, logger) catch |err| {
```

Then, between `const result = ...` succeeding and `all_results.append(...)`, insert:
```zig
        if (bench) |b| {
            const summary = result.stats.getSummary();
            b.scan_ns       += nsElapsed(t_scan);
            b.files_total   += summary.total;
            b.files_source  += result.file_entries.count();
            b.files_binary  += result.binary_entries.count();
            b.files_ignored += summary.ignored;
        }
```

- [ ] **Step 3: Pass `bench` to `writePathReports` call**

Inside `exec()`, the `writePathReports` call (currently around line 348) reads:
```zig
        writePathReports(result, cfg, &pool, allocator, logger) catch |err| {
```
Change to:
```zig
        writePathReports(result, cfg, &pool, allocator, logger, bench) catch |err| {
```

- [ ] **Step 4: Update both `runner.exec` callers in `main.zig` to pass `null`**

Line ~90 (serve path):
```zig
_ = runner.exec(&typedCfg, &cache, allocator) catch |err| {
```
→
```zig
_ = runner.exec(&typedCfg, &cache, allocator, null) catch |err| {
```

Line ~147 (run path):
```zig
_ = runner.exec(&typedCfg, &cache, allocator) catch |err| {
```
→
```zig
_ = runner.exec(&typedCfg, &cache, allocator, null) catch |err| {
```

- [ ] **Step 5: Run tests**

```bash
cd /home/anze/Projects/zigzag && make test 2>&1 | tail -5
```
Expected: `207 passed; 1 skipped; 0 failed.`

- [ ] **Step 6: Commit**

```bash
cd /home/anze/Projects/zigzag && git add src/cli/commands/runner.zig src/main.zig && git commit -m "feat: add bench param to runner.exec() with scan phase timing"
```

---

### Task 3: Instrument `writePathReports()` with aggregate + write-phase timing

**Files:**
- Modify: `src/cli/commands/runner.zig` — `writePathReports()` signature + body (lines 170–231)

- [ ] **Step 1: Add `bench` parameter to `writePathReports()` signature**

Change the function signature from:
```zig
fn writePathReports(
    result: *const ScanResult,
    cfg: *const Config,
    pool: *Pool,
    allocator: std.mem.Allocator,
    logger: ?*Logger,
) !void {
```
to:
```zig
fn writePathReports(
    result: *const ScanResult,
    cfg: *const Config,
    pool: *Pool,
    allocator: std.mem.Allocator,
    logger: ?*Logger,
    bench: ?*BenchResult,
) !void {
```

- [ ] **Step 2: Replace the body of `writePathReports()` with the instrumented version**

Replace everything from `_ = pool;` to the final `}` with:

```zig
    _ = pool; // reserved for future use

    const output_filename: []const u8 = if (cfg.output) |o| o else "report.md";
    const md_path = try report.resolveOutputPath(allocator, cfg, result.root_path, output_filename);
    defer allocator.free(md_path);

    // HTML content sidecar — timer starts here so it folds into write_html_ns.
    const t_html = std.time.nanoTimestamp();
    if (cfg.html_output) {
        const html_path_for_content = try report.deriveHtmlPath(allocator, md_path);
        defer allocator.free(html_path_for_content);
        const content_dir = try report.deriveContentDir(allocator, html_path_for_content);
        defer allocator.free(content_dir);
        try report.writeContentFiles(&result.file_entries, content_dir, allocator);
        lg.printSuccess("Content dir:   {s}/", .{content_dir});
        if (logger) |l| l.log("Content files written: {s}/", .{content_dir});
    }

    // Aggregate — timer starts after content sidecar.
    const t_agg = std.time.nanoTimestamp();
    var report_data = try report.ReportData.init(allocator, &result.file_entries, &result.binary_entries, cfg.timezone_offset);
    defer report_data.deinit();
    if (bench) |b| b.aggregate_ns += nsElapsed(t_agg);

    // write-md
    const t_md = std.time.nanoTimestamp();
    try report.writeReport(&report_data, &result.file_entries, md_path, result.root_path, cfg, allocator);
    lg.printSuccess("Report written: {s}", .{md_path});
    if (logger) |l| l.log("Report written: {s}", .{md_path});
    if (bench) |b| {
        b.write_md_ns += nsElapsed(t_md);
        b.md_bytes    += fileSizeOf(md_path);
    }

    // write-json
    if (cfg.json_output) {
        const json_path = try report.deriveJsonPath(allocator, md_path);
        defer allocator.free(json_path);
        const t_json = std.time.nanoTimestamp();
        try report.writeJsonReport(&report_data, json_path, result.root_path, cfg, allocator);
        lg.printSuccess("JSON report: {s}", .{json_path});
        if (logger) |l| l.log("JSON report written: {s}", .{json_path});
        if (bench) |b| {
            b.write_json_ns += nsElapsed(t_json);
            b.json_bytes    += fileSizeOf(json_path);
        }
    }

    // write-html (t_html started before content sidecar, so covers both)
    if (cfg.html_output) {
        const html_path = try report.deriveHtmlPath(allocator, md_path);
        defer allocator.free(html_path);
        try report.writeHtmlReport(&report_data, html_path, result.root_path, cfg, allocator);
        lg.printSuccess("HTML report: {s}", .{html_path});
        if (logger) |l| l.log("HTML report written: {s}", .{html_path});
        if (bench) |b| {
            b.write_html_ns += nsElapsed(t_html);
            b.html_bytes    += fileSizeOf(html_path);
        }
    }

    // write-llm
    if (cfg.llm_report) {
        const llm_path = try report.deriveLlmPath(allocator, md_path);
        defer allocator.free(llm_path);
        const t_llm = std.time.nanoTimestamp();
        try report.writeLlmReport(&report_data, result.binary_entries.count(), llm_path, result.root_path, cfg, allocator);
        lg.printSuccess("LLM report: {s}", .{llm_path});
        if (logger) |l| l.log("LLM report written: {s}", .{llm_path});
        if (bench) |b| {
            b.write_llm_ns += nsElapsed(t_llm);
            b.llm_bytes    += fileSizeOf(llm_path);
        }
    }

    const sv = result.stats.getSummary();
    lg.printSummary(result.root_path, sv.total, sv.source, sv.cached, sv.processed, sv.binary, sv.ignored);
    if (logger) |l| {
        l.log("Summary: total={d}, source={d}, cached={d}, fresh={d}, binary={d}, ignored={d}", .{
            sv.total, sv.source, sv.cached, sv.processed, sv.binary, sv.ignored,
        });
    }
```

- [ ] **Step 3: Run tests**

```bash
cd /home/anze/Projects/zigzag && make test 2>&1 | tail -5
```
Expected: `207 passed; 1 skipped; 0 failed.`

- [ ] **Step 4: Commit**

```bash
cd /home/anze/Projects/zigzag && git add src/cli/commands/runner.zig && git commit -m "feat: instrument writePathReports with per-phase bench timing"
```

---

## Chunk 2: bench.zig, main.zig wiring, tests

### Task 4: Create `src/cli/commands/bench.zig`

**Files:**
- Create: `src/cli/commands/bench.zig`

- [ ] **Step 1: Write a failing test for `printTable` in `bench_test.zig`**

Create `src/cli/commands/bench_test.zig`:

```zig
const std = @import("std");
const bench = @import("./bench.zig");
const runner = @import("./runner.zig");

test "printTable does not panic with populated BenchResult" {
    var result = runner.BenchResult{
        .scan_ns       = 340_000_000,
        .aggregate_ns  = 12_000_000,
        .write_md_ns   = 8_000_000,
        .write_json_ns = 60_000_000,
        .write_html_ns = 45_000_000,
        .write_llm_ns  = 0,
        .files_total   = 1423,
        .files_source  = 1350,
        .files_binary  = 50,
        .files_ignored = 23,
        .md_bytes      = 46_080,
        .json_bytes    = 122_880,
        .html_bytes    = 2_202_009,
        .llm_bytes     = 0,
    };
    bench.printTable(&result);
}

test "printTable with all-zero BenchResult does not panic" {
    var result: runner.BenchResult = .{};
    bench.printTable(&result);
}
```

- [ ] **Step 2: Run the test — expect compile failure (bench.zig doesn't exist yet)**

```bash
cd /home/anze/Projects/zigzag && zig test --dep options \
  -Mroot=src/cli/commands/bench_test.zig \
  -Moptions=src/cli/version/fallback.zig 2>&1 | head -10
```
Expected: error about missing `bench.zig`.

- [ ] **Step 3: Create `src/cli/commands/bench.zig`**

Follows the same `pos += (...).len` buffer pattern used in `src/utils/logger/logger.zig`.
`std.fs.File.stderr()` is the correct Zig 0.15.2 API (confirmed by `logger.zig`).
`fmtBytes` writes into the caller-provided `buf` to avoid returning a slice into a local stack variable.

```zig
const std = @import("std");
const Config = @import("config/config.zig").Config;
const CacheImpl = @import("../../cache/impl.zig").CacheImpl;
const runner = @import("runner.zig");

pub fn execBench(cfg: *const Config, allocator: std.mem.Allocator) !void {
    const cache_path = try std.fs.path.join(allocator, &.{ ".", ".cache" });
    defer allocator.free(cache_path);

    var cache = try CacheImpl.init(allocator, cache_path, cfg.small_threshold);
    defer cache.deinit();

    var result: runner.BenchResult = .{};
    try runner.exec(cfg, &cache, allocator, &result);
    printTable(&result);
}

/// Prints a per-phase timing table to stderr.
/// Phases with zero duration are omitted.
pub fn printTable(result: *const runner.BenchResult) void {
    const total_ns = result.scan_ns + result.aggregate_ns +
        result.write_md_ns + result.write_json_ns +
        result.write_html_ns + result.write_llm_ns;
    if (total_ns == 0) return;

    const sep = "  ──────────────────────────────────────────────────────────";
    var buf: [4096]u8 = undefined;
    var pos: usize = 0;

    pos += (std.fmt.bufPrint(buf[pos..], "\n{s}\n", .{sep}) catch return).len;
    pos += (std.fmt.bufPrint(buf[pos..], "  {s:<16} {s:>10}   {s:<24} {s:>8}\n", .{
        "Phase", "Duration", "Context", "% Total",
    }) catch return).len;
    pos += (std.fmt.bufPrint(buf[pos..], "{s}\n", .{sep}) catch return).len;

    var ctx_buf: [32]u8 = undefined;

    if (result.scan_ns > 0) {
        const ctx = std.fmt.bufPrint(&ctx_buf, "{d} files", .{result.files_total}) catch "?";
        pos += appendRow(buf[pos..], "scan", result.scan_ns, total_ns, ctx) catch return;
    }
    if (result.aggregate_ns > 0) {
        const ctx = std.fmt.bufPrint(&ctx_buf, "{d} entries", .{result.files_source}) catch "?";
        pos += appendRow(buf[pos..], "aggregate", result.aggregate_ns, total_ns, ctx) catch return;
    }
    if (result.write_md_ns > 0) {
        const ctx = fmtBytes(&ctx_buf, result.md_bytes, false);
        pos += appendRow(buf[pos..], "write-md", result.write_md_ns, total_ns, ctx) catch return;
    }
    if (result.write_json_ns > 0) {
        const ctx = fmtBytes(&ctx_buf, result.json_bytes, false);
        pos += appendRow(buf[pos..], "write-json", result.write_json_ns, total_ns, ctx) catch return;
    }
    if (result.write_html_ns > 0) {
        const ctx = fmtBytes(&ctx_buf, result.html_bytes, true);
        pos += appendRow(buf[pos..], "write-html", result.write_html_ns, total_ns, ctx) catch return;
    }
    if (result.write_llm_ns > 0) {
        const ctx = fmtBytes(&ctx_buf, result.llm_bytes, false);
        pos += appendRow(buf[pos..], "write-llm", result.write_llm_ns, total_ns, ctx) catch return;
    }

    const total_ms = total_ns / 1_000_000;
    var dur_buf: [16]u8 = undefined;
    const total_dur: []const u8 = if (total_ms == 0)
        std.fmt.bufPrint(&dur_buf, "< 1 ms", .{}) catch "< 1 ms"
    else
        std.fmt.bufPrint(&dur_buf, "{d} ms", .{total_ms}) catch "? ms";

    pos += (std.fmt.bufPrint(buf[pos..], "{s}\n", .{sep}) catch return).len;
    pos += (std.fmt.bufPrint(buf[pos..], "  {s:<16} {s:>10}\n\n", .{ "total", total_dur }) catch return).len;

    std.fs.File.stderr().writeAll(buf[0..pos]) catch {};
}

/// Appends one table row into `buf`. Returns bytes written, or NoSpaceLeft.
fn appendRow(buf: []u8, name: []const u8, phase_ns: u64, total_ns: u64, ctx: []const u8) error{NoSpaceLeft}!usize {
    const ms = phase_ns / 1_000_000;
    const pct = phase_ns * 100 / total_ns;
    var dur_buf: [16]u8 = undefined;
    const dur: []const u8 = if (ms == 0)
        std.fmt.bufPrint(&dur_buf, "< 1 ms", .{}) catch "< 1 ms"
    else
        std.fmt.bufPrint(&dur_buf, "{d} ms", .{ms}) catch "? ms";
    const written = try std.fmt.bufPrint(buf,
        "  {s:<16} {s:>10}   {s:<24} {d:>7}%\n",
        .{ name, dur, ctx, pct });
    return written.len;
}

/// Formats `n` bytes as human-readable string into `buf`.
/// `html = true` appends " (w/ content)" to indicate the HTML content sidecar is included.
/// Returns a slice into `buf` — caller must not write to `buf` before consuming the result.
fn fmtBytes(buf: []u8, n: u64, html: bool) []const u8 {
    if (n == 0) return "—";
    const mb = @as(f64, @floatFromInt(n)) / (1024.0 * 1024.0);
    const kb = @as(f64, @floatFromInt(n)) / 1024.0;
    const suffix: []const u8 = if (html) " (w/ content)" else "";
    if (n >= 1024 * 1024)
        return std.fmt.bufPrint(buf, "{d:.1} MB{s}", .{ mb, suffix }) catch "?";
    if (n >= 1024)
        return std.fmt.bufPrint(buf, "{d:.1} KB{s}", .{ kb, suffix }) catch "?";
    return std.fmt.bufPrint(buf, "{d} B{s}", .{ n, suffix }) catch "?";
}
```

- [ ] **Step 4: Run the bench_test.zig tests**

```bash
cd /home/anze/Projects/zigzag && zig test --dep options \
  -Mroot=src/cli/commands/bench_test.zig \
  -Moptions=src/cli/version/fallback.zig 2>&1
```
Expected: both tests pass.

- [ ] **Step 5: Run full test suite**

```bash
cd /home/anze/Projects/zigzag && make test 2>&1 | tail -5
```
Expected: `207 passed; 1 skipped; 0 failed.`

- [ ] **Step 6: Commit**

```bash
cd /home/anze/Projects/zigzag && git add src/cli/commands/bench.zig src/cli/commands/bench_test.zig \
  && git commit -m "feat: add bench.zig with execBench and printTable"
```

---

### Task 5: Wire `bench` subcommand in `main.zig`

**Files:**
- Modify: `src/main.zig`

- [ ] **Step 1: Add import and `is_bench_command` declaration**

At the top of `main.zig`, add after the `serve` import (line 5):
```zig
const bench = @import("./cli/commands/bench.zig");
```

In `main()`, add after `var is_serve_command = false;` (line 28):
```zig
var is_bench_command = false;
```

- [ ] **Step 2: Detect `bench` subcommand in the arg-parsing loop**

In the `while (args.next()) |arg|` loop, insert after the `serve` detection block (after line 44, the `continue;` line) and **before** the `if (std.mem.startsWith(u8, arg, "--"))` block at line 46. If inserted after line 46, the `else` branch will treat `"bench"` as an unknown argument and return early.

```zig
        if (std.mem.eql(u8, arg, "bench")) {
            is_bench_command = true;
            is_run_command = true;
            continue;
        }
```

- [ ] **Step 3: Add bench dispatch before the `is_serve_command` block**

In the `Success` branch (inside `switch (result)`), insert before the `if (is_serve_command)` block (before line 70):

```zig
            if (is_bench_command) {
                if (typedCfg.paths.items.len == 0) {
                    lg.printError("bench requires at least one path (--path or zig.conf.json)", .{});
                    return;
                }
                try bench.execBench(&typedCfg, allocator);
                return;
            }
```

- [ ] **Step 4: Run full test suite**

```bash
cd /home/anze/Projects/zigzag && make test 2>&1 | tail -5
```
Expected: `207 passed; 1 skipped; 0 failed.`

- [ ] **Step 5: Smoke-test manually**

```bash
cd /home/anze/Projects/zigzag && zig build && ./zig-out/bin/zigzag bench --path ./src 2>&1
```
Expected: normal runner output followed by a timing table with at least `scan`, `aggregate`, and `write-md` rows.

- [ ] **Step 6: Commit**

```bash
cd /home/anze/Projects/zigzag && git add src/main.zig \
  && git commit -m "feat: wire bench subcommand in main.zig"
```

---

### Task 6: Update help text and register bench_test in root.zig

**Files:**
- Modify: `src/cli/handlers/help.zig`
- Modify: `src/root.zig`

- [ ] **Step 1: Add `bench` to help text**

In `src/cli/handlers/help.zig`, in the `printHelp` multiline string, add `bench` to the Commands section:

```
\\  bench           Run with per-phase timing instrumentation
```
Insert after the `run` line.

- [ ] **Step 2: Add bench_test to root.zig**

In `src/root.zig`, add after the `serve_test` import line:
```zig
    _ = @import("./cli/commands/bench_test.zig");
```

- [ ] **Step 3: Run full test suite — expect one new test**

```bash
cd /home/anze/Projects/zigzag && make test 2>&1 | grep -E "passed|bench"
```
Expected: `209 passed; 1 skipped; 0 failed.` (two new bench tests added).

- [ ] **Step 4: Commit**

```bash
cd /home/anze/Projects/zigzag && git add src/cli/handlers/help.zig src/root.zig \
  && git commit -m "feat: register bench tests and add bench to help text"
```
