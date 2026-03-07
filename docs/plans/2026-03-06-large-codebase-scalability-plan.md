# Large-Codebase Scalability Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Scale ZigZag to handle 300k+ file repos (e.g. Next.js) without OOM or browser hangs by separating source content from HTML, adding lazy browser loading, arena allocators, a `zigzag serve` command, incremental SSE, and parallel directory walking.

**Architecture:** Five independent phases each shippable and testable alone. Phase 1 is the highest-impact change — it removes the 3× memory multiplier in `writeHtmlReport` (content map JSON + HTML assembly buffer = ~3.8 GB for a 300k-file repo) by moving source content to a sidecar `report-content.json` streamed per-entry from the in-memory `file_entries` map. The HTML stays small (metadata only); the browser fetches content on demand.

**Tech Stack:** Zig 0.15.2, `std.json.Stringify`, `std.io.bufferedWriter`, `std.Thread`, `std.Thread.Mutex`/`Condition`, existing Pool/WaitGroup pattern.

**Test command:** `zig test --dep options -Mroot=src/root.zig -Moptions=src/cli/options_fallback.zig`
**Build command:** `zig build`
**Run command:** `zig build run -- --path ./src`

---

## Phase 1 — Streaming content.json + Metadata-only HTML + file:// Fallback

Fixes: HTML OOM, browser parse hang, offline UX.

Memory before: `~4–6 GB` peak (HashMap + 3 in-memory HTML buffers).
Memory after: `~1.8 GB` (HashMap only; HTML buffers eliminated).

---

### Task 1.1: Add `deriveContentPath` helper

**Files:**
- Modify: `src/cli/commands/report/paths/paths.zig`
- Modify: `src/cli/commands/report/paths/paths_test.zig`
- Modify: `src/cli/commands/report.zig` (re-export)

**Step 1: Write the failing test**

In `src/cli/commands/report/paths/paths_test.zig`, add:

```zig
test "deriveContentPath replaces .html with -content.json" {
    const alloc = std.testing.allocator;
    const result = try paths.deriveContentPath(alloc, "zigzag-reports/report.html");
    defer alloc.free(result);
    try std.testing.expectEqualStrings("zigzag-reports/report-content.json", result);
}

test "deriveContentPath handles no .html extension" {
    const alloc = std.testing.allocator;
    const result = try paths.deriveContentPath(alloc, "zigzag-reports/report");
    defer alloc.free(result);
    try std.testing.expectEqualStrings("zigzag-reports/report-content.json", result);
}
```

**Step 2: Run test to confirm it fails**

```bash
zig test --dep options -Mroot=src/root.zig -Moptions=src/cli/options_fallback.zig 2>&1 | grep -A2 "deriveContentPath"
```

Expected: compile error — `deriveContentPath` undefined.

**Step 3: Implement `deriveContentPath` in `paths.zig`**

Following the pattern of `deriveJsonPath` / `deriveHtmlPath` already in that file:

```zig
/// Derive the content JSON sidecar path from an HTML report path.
/// report.html → report-content.json
/// report      → report-content.json
pub fn deriveContentPath(allocator: std.mem.Allocator, html_path: []const u8) ![]u8 {
    if (std.mem.endsWith(u8, html_path, ".html")) {
        const base = html_path[0 .. html_path.len - ".html".len];
        return std.fmt.allocPrint(allocator, "{s}-content.json", .{base});
    }
    return std.fmt.allocPrint(allocator, "{s}-content.json", .{html_path});
}
```

Re-export from `src/cli/commands/report.zig`:
```zig
pub const deriveContentPath = @import("report/paths/paths.zig").deriveContentPath;
```

**Step 4: Run tests to confirm pass**

```bash
zig test --dep options -Mroot=src/root.zig -Moptions=src/cli/options_fallback.zig 2>&1 | tail -5
```

Expected: `All N tests passed.`

**Step 5: Commit**

```bash
git add src/cli/commands/report/paths/paths.zig src/cli/commands/report/paths/paths_test.zig src/cli/commands/report.zig
git commit -m "feat(report): add deriveContentPath for content.json sidecar"
```

---

### Task 1.2: Add `writeContentJson` streaming writer

**Files:**
- Modify: `src/cli/commands/report/writers/html/html.zig`

Write a new exported function in `html.zig` (same file; it owns the HTML output pipeline):

**Step 1: Write the failing test**

This function does file I/O so we test it with a temp dir. In `src/cli/commands/report/writers/html/html_test.zig` (create if missing), add:

```zig
const std = @import("std");
const html = @import("html.zig");
const JobEntry = @import("../../../../../jobs/entry.zig").JobEntry;

test "writeContentJson streams valid JSON object" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const out_path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(out_path);
    const content_path = try std.fs.path.join(alloc, &.{ out_path, "content.json" });
    defer alloc.free(content_path);

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();

    const content1: []u8 = try alloc.dupe(u8, "hello world");
    defer alloc.free(content1);
    const path1: []const u8 = "src/main.zig";
    try file_entries.put(path1, .{
        .path = path1, .content = content1,
        .size = 11, .mtime = 0, .extension = ".zig", .line_count = 1,
    });

    try html.writeContentJson(&file_entries, content_path, alloc);

    const written = try std.fs.cwd().readFileAlloc(alloc, content_path, 1024 * 1024);
    defer alloc.free(written);

    // Must be valid JSON object containing the path key
    try std.testing.expect(std.mem.indexOf(u8, written, "src/main.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "hello world") != null);
    try std.testing.expect(written[0] == '{');
    try std.testing.expect(written[written.len - 1] == '}');
}

test "writeContentJson produces no trailing comma with multiple entries" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const out_path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(out_path);
    const content_path = try std.fs.path.join(alloc, &.{ out_path, "content.json" });
    defer alloc.free(content_path);

    var file_entries = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries.deinit();

    const c1: []u8 = try alloc.dupe(u8, "aaa");
    const c2: []u8 = try alloc.dupe(u8, "bbb");
    defer alloc.free(c1);
    defer alloc.free(c2);
    try file_entries.put("a.zig", .{ .path = "a.zig", .content = c1, .size = 3, .mtime = 0, .extension = ".zig", .line_count = 1 });
    try file_entries.put("b.zig", .{ .path = "b.zig", .content = c2, .size = 3, .mtime = 0, .extension = ".zig", .line_count = 1 });

    try html.writeContentJson(&file_entries, content_path, alloc);

    const written = try std.fs.cwd().readFileAlloc(alloc, content_path, 1024 * 1024);
    defer alloc.free(written);

    // Parse to verify valid JSON
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, written, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(std.json.Value.object, std.meta.activeTag(parsed.value));
    try std.testing.expectEqual(@as(usize, 2), parsed.value.object.count());
}
```

Add `html_test.zig` to `src/root.zig`:
```zig
_ = @import("./cli/commands/report/writers/html/html_test.zig");
```

**Step 2: Run test to confirm it fails**

```bash
zig test --dep options -Mroot=src/root.zig -Moptions=src/cli/options_fallback.zig 2>&1 | grep -E "error|FAIL" | head -10
```

Expected: compile error — `writeContentJson` undefined.

**Step 3: Implement `writeContentJson` in `html.zig`**

Add this function to `html.zig`. It iterates the HashMap and writes one JSON key:value pair at a time — peak memory = O(max_single_file_size).

```zig
/// Stream source content to a sidecar JSON file: {"path":"content",...}.
/// Each entry is JSON-encoded individually and written to disk — O(max_file_size) peak RAM.
pub fn writeContentJson(
    file_entries: *const std.StringHashMap(JobEntry),
    content_path: []const u8,
    allocator: std.mem.Allocator,
) !void {
    var file = try std.fs.cwd().createFile(content_path, .{ .truncate = true });
    defer file.close();

    var bw = std.io.bufferedWriter(file.writer());
    const w = bw.writer();

    try w.writeByte('{');
    var first = true;
    var it = file_entries.iterator();
    while (it.next()) |kv| {
        if (!first) try w.writeByte(',');
        first = false;

        // JSON-encode the key (path)
        const key_json = try std.json.stringifyAlloc(allocator, kv.key_ptr.*, .{});
        defer allocator.free(key_json);
        try w.writeAll(key_json);
        try w.writeByte(':');

        // JSON-encode the value (source content)
        const val_json = try std.json.stringifyAlloc(allocator, kv.value_ptr.content, .{});
        defer allocator.free(val_json);
        try w.writeAll(val_json);
    }
    try w.writeByte('}');
    try bw.flush();
}
```

**Step 4: Run tests to confirm pass**

```bash
zig test --dep options -Mroot=src/root.zig -Moptions=src/cli/options_fallback.zig 2>&1 | tail -5
```

Expected: `All N tests passed.`

**Step 5: Commit**

```bash
git add src/cli/commands/report/writers/html/html.zig src/cli/commands/report/writers/html/html_test.zig src/root.zig
git commit -m "feat(report): add writeContentJson streaming sidecar writer"
```

---

### Task 1.3: Remove content embedding from `writeHtmlReport`

The current `writeHtmlReport` builds a 1.8 GB content JSON buffer and a 2 GB HTML assembly buffer. We remove both.

**Files:**
- Modify: `src/cli/commands/report/writers/html/html.zig`
- Modify: `src/templates/src/template.html` (remove `__ZIGZAG_CONTENT__` script block)
- Modify: `src/templates/dashboard.html` (regenerate from template)

**Step 1: Update `writeHtmlReport` signature and body**

The function currently has two markers: `__ZIGZAG_DATA__` (metadata) and `__ZIGZAG_CONTENT__` (content map). Remove the content marker and everything that builds the content buffer.

Replace the body of `writeHtmlReport` from the content section onward:

```zig
// --- REMOVE these lines entirely ---
//   const content_marker = "__ZIGZAG_CONTENT__";
//   const content_split_pos = ...
//   var content_aw: std.io.Writer.Allocating = ...
//   var cws: ... (content JSON building loop)
//   const content_raw = ...
//   const content_safe = ...
//   ...dashboard_template[split_pos + marker.len .. content_split_pos]...
//   ...content_safe...
//   ...dashboard_template[content_split_pos + content_marker.len ..]...

// --- REPLACE final assembly with ---
// Assemble: prefix + report_json + rest-of-template
var aw: std.io.Writer.Allocating = .init(allocator);
defer aw.deinit();
try aw.writer.writeAll(dashboard_template[0..split_pos]);
try aw.writer.writeAll(json_safe);
try aw.writer.writeAll(dashboard_template[split_pos + marker.len ..]);

// Write to disk
var html_file = try std.fs.cwd().createFile(html_path, .{ .truncate = true });
defer html_file.close();
try html_file.writeAll(aw.written());
```

The template no longer has a `__ZIGZAG_CONTENT__` marker, so `dashboard_template[split_pos + marker.len ..]` now covers the rest of the template cleanly.

**Step 2: Update `template.html` — remove content script tag**

In `src/templates/src/template.html`, find and remove the `<script>` block that contains `__ZIGZAG_CONTENT__`:

```html
<!-- REMOVE this entire block: -->
<script id="zigzag-content" type="application/json">
__ZIGZAG_CONTENT__
</script>
```

**Step 3: Regenerate `dashboard.html`**

```bash
cd /home/anze/Projects/zigzag && python3 src/templates/bundle.py
```

Verify the `__ZIGZAG_CONTENT__` marker is gone:

```bash
grep -c "__ZIGZAG_CONTENT__" src/templates/dashboard.html
```

Expected: `0`

**Step 4: Build and verify no compile errors**

```bash
zig build 2>&1 | head -20
```

Expected: clean build.

**Step 5: Commit**

```bash
git add src/cli/commands/report/writers/html/html.zig src/templates/src/template.html src/templates/dashboard.html
git commit -m "feat(html): remove embedded content from report.html — use content.json sidecar"
```

---

### Task 1.4: Wire `writeContentJson` into the runner

**Files:**
- Modify: `src/cli/commands/runner.zig`

After `wg.wait()` completes (all files processed, `file_entries` fully populated), call `writeContentJson` before report writing. Also add `report-content.json` to the ignore list.

**Step 1: Locate insertion point in `runner.zig`**

Find the line after `wg.wait();` in `processPath`. Currently:
```zig
wg.wait();
// ... logging ...
var report_data = try report.ReportData.init(...);
```

**Step 2: Add ignore list entry for content.json**

In the ignore list setup block (near where `html_ignore`, `json_ignore` are added):

```zig
if (cfg.html_output) {
    const html_ignore = try report.deriveHtmlPath(allocator, md_path);
    try file_ctx.ignore_list.append(allocator, html_ignore);
    // Also ignore the content sidecar
    const content_ignore = try report.deriveContentPath(allocator, html_ignore);
    try file_ctx.ignore_list.append(allocator, content_ignore);
}
```

**Step 3: Add `writeContentJson` call after `wg.wait()`**

After `wg.wait();` and before `report.ReportData.init(...)`:

```zig
// Stream source content to sidecar file (O(max_file_size) peak RAM).
// Must complete before HTML report is written (HTML no longer embeds content).
if (cfg.html_output) {
    const html_path_tmp = try report.deriveHtmlPath(allocator, md_path);
    defer allocator.free(html_path_tmp);
    const content_path = try report.deriveContentPath(allocator, html_path_tmp);
    defer allocator.free(content_path);
    try report.writeContentJson(&file_entries, content_path, allocator);
    lg.printSuccess("Content JSON: {s}", .{content_path});
}
```

**Step 4: Re-export `writeContentJson` from `report.zig`**

In `src/cli/commands/report.zig`:
```zig
pub const writeContentJson = @import("report/writers/html/html.zig").writeContentJson;
```

**Step 5: Build and smoke-test**

```bash
zig build
zig build run -- --path ./src --html
ls zigzag-reports/
```

Expected: `report.md  report.html  report-content.json`

Verify `report.html` size is now small:
```bash
wc -c zigzag-reports/report.html zigzag-reports/report-content.json
```

`report.html` should be under 1 MB. `report-content.json` holds the content.

**Step 6: Commit**

```bash
git add src/cli/commands/runner.zig src/cli/commands/report.zig
git commit -m "feat(runner): stream content.json sidecar after scan, before HTML generation"
```

---

### Task 1.5: Browser lazy loading + file:// fallback

**Files:**
- Modify: `src/templates/src/dashboard.js`
- Modify: `src/templates/src/template.html` (add offline banner HTML)
- Modify: `src/templates/dashboard.html` (regenerate)

**Step 1: Add offline banner HTML to `template.html`**

Add a hidden banner element in the `<body>` (before the main app div):

```html
<div id="offline-banner" style="display:none;position:fixed;top:0;left:0;right:0;z-index:9999;
  background:#1a1a2e;color:#e2e8f0;padding:1.5rem 2rem;font-family:monospace;
  border-bottom:2px solid #f6ad55;line-height:1.7">
  <strong style="color:#f6ad55">⚠ Source files require a local server.</strong><br>
  Run: <code style="background:#2d2d44;padding:2px 8px;border-radius:4px">zigzag serve</code>
  then open
  <code style="background:#2d2d44;padding:2px 8px;border-radius:4px">http://localhost:8787</code>
  <button onclick="document.getElementById('offline-banner').style.display='none'"
    style="float:right;background:none;border:1px solid #718096;color:#a0aec0;
    padding:4px 12px;cursor:pointer;border-radius:4px">Dismiss</button>
</div>
```

**Step 2: Replace content map access in `dashboard.js`**

Find all references to `window.CONTENT_MAP` (or the embedded content variable, check what name the current template uses for the content script). Replace with a lazy-fetch pattern:

```js
// Content cache — loaded lazily from report-content.json on first file open.
let _contentCache = null;
let _contentLoadFailed = false;

function showOfflineBanner() {
    const banner = document.getElementById('offline-banner');
    if (banner) banner.style.display = 'block';
}

async function getFileContent(path) {
    if (_contentLoadFailed) return null;
    if (_contentCache) return _contentCache[path] ?? null;

    if (location.protocol === 'file:') {
        showOfflineBanner();
        _contentLoadFailed = true;
        return null;
    }

    try {
        // Derive content.json path relative to current page
        const contentUrl = location.href.replace(/\/[^/]*$/, '/') + 'report-content.json';
        const res = await fetch(contentUrl);
        if (!res.ok) throw new Error('HTTP ' + res.status);
        _contentCache = await res.json();
        return _contentCache[path] ?? null;
    } catch (e) {
        console.warn('ZigZag: failed to load content.json:', e.message);
        showOfflineBanner();
        _contentLoadFailed = true;
        return null;
    }
}
```

Replace all existing synchronous `CONTENT_MAP[path]` accesses with `await getFileContent(path)`. The file-open handlers should already be async (they do highlighting). If not, make them async.

**Step 3: Regenerate bundle**

```bash
cd /home/anze/Projects/zigzag && python3 src/templates/bundle.py
```

Run bundle tests:
```bash
cd src/templates && python3 test_bundle.py -v
```

Expected: all tests pass.

**Step 4: Build and manual test**

```bash
zig build
zig build run -- --path ./src --html
```

Open `zigzag-reports/report.html` directly (file://) — should see offline banner.

Open via `python3 -m http.server 8000` from `zigzag-reports/` — source content should load.

**Step 5: Commit**

```bash
git add src/templates/src/dashboard.js src/templates/src/template.html src/templates/dashboard.html
git commit -m "feat(dashboard): lazy-load content.json, graceful file:// offline fallback"
```

---

### Task 1.6: Mirror content.json in watch mode

**Files:**
- Modify: `src/cli/commands/watch/state.zig` (ignore list)
- Modify: `src/cli/commands/watch/reporter.zig` (call writeContentJson)

**Step 1: Add content.json to watch ignore list**

In `state.zig` `buildIgnoreList`, add alongside `html_ignore`:

```zig
if (cfg.html_output) {
    const html_ign = try report.deriveHtmlPath(alloc, self.md_path);
    try self.file_ctx.ignore_list.append(alloc, html_ign);
    const content_ign = try report.deriveContentPath(alloc, html_ign);
    try self.file_ctx.ignore_list.append(alloc, content_ign);
}
```

**Step 2: Call `writeContentJson` in watch reporter**

In `watch/reporter.zig` (or wherever `writeAllReports` is defined), after the HTML report call, add:

```zig
if (cfg.html_output) {
    const html_p = report.deriveHtmlPath(allocator, state.md_path) catch return;
    defer allocator.free(html_p);
    const content_p = report.deriveContentPath(allocator, html_p) catch return;
    defer allocator.free(content_p);
    report.writeContentJson(&state.file_entries, content_p, allocator) catch |err| {
        lg.printError("content.json failed: {s}", .{@errorName(err)});
    };
}
```

**Step 3: Build and verify**

```bash
zig build
zig build run -- --path ./src --html --watch
```

Verify `zigzag-reports/report-content.json` is created and updated on file changes.

**Step 4: Commit**

```bash
git add src/cli/commands/watch/state.zig src/cli/commands/watch/reporter.zig
git commit -m "feat(watch): write and ignore content.json sidecar in watch mode"
```

---

## Phase 2 — Arena Allocators + Fix page_allocator + FIFO Queue

Fixes: 10–50× allocation throughput by eliminating per-file syscalls.

---

### Task 2.1: Add `thread_allocator` to `Job` struct

**Files:**
- Modify: `src/jobs/job.zig`

**Step 1: Read the current Job struct**

```bash
cat src/jobs/job.zig
```

**Step 2: Add field**

```zig
pub const Job = struct {
    path: []const u8,
    file_ctx: ?*FileContext,
    cache: ?*CacheImpl,
    stats: *ProcessStats,
    file_entries: *std.StringHashMap(JobEntry),
    binary_entries: *std.StringHashMap(BinaryEntry),
    entries_mutex: *std.Thread.Mutex,
    allocator: std.mem.Allocator,
    thread_allocator: std.mem.Allocator, // ← NEW: per-thread arena, reset after each job
};
```

**Step 3: Fix all construction sites**

Find everywhere `Job{...}` is constructed:
```bash
grep -rn "Job{" src/
```

Add `thread_allocator: allocator` to each construction site as a temporary placeholder (will be wired to actual arena in Task 2.3).

**Step 4: Build to confirm no errors**

```bash
zig build 2>&1 | head -20
```

**Step 5: Commit**

```bash
git add src/jobs/job.zig src/walker/callback.zig src/cli/commands/watch/state.zig
git commit -m "feat(jobs): add thread_allocator field to Job for per-thread arena support"
```

---

### Task 2.2: Fix `page_allocator` usage in `processFileJob`

**Files:**
- Modify: `src/jobs/process.zig`

**Step 1: Find all `page_allocator` references**

```bash
grep -n "page_allocator" src/jobs/process.zig
```

Currently line 173: `const allocator = std.heap.page_allocator;`

**Step 2: Replace with `job.thread_allocator`**

Remove the `const allocator = std.heap.page_allocator;` line.

Change the function signature to use `job.thread_allocator` for all allocations that are per-file temporaries. For allocations that must OUTLIVE the job (path copies stored in the mutex-protected HashMap), continue using `job.allocator` (the long-lived GPA allocator passed from runner).

Key distinction:
- `path_copy`, `ext_copy`, `content` stored in HashMap → use `job.allocator` (persists)
- Temporary buffers local to the job → use `job.thread_allocator` (arena, reset after job)

In practice, `processFileJob` currently uses `allocator` for both `readFileAlloc` (content → stored in HashMap) and path/ext copies. Both need to persist so they should use `job.allocator`. The arena (`job.thread_allocator`) is used for any scratch work within the job.

Change line 173:
```zig
// BEFORE:
const allocator = std.heap.page_allocator;

// AFTER:
const allocator = job.allocator; // long-lived: HashMap entries must outlive this job
```

**Step 3: Fix `state.zig` page_allocator usage**

```bash
grep -n "page_allocator" src/cli/commands/watch/state.zig
```

Lines 150-158: `freeJobEntry` and `freeBinaryEntry` use `std.heap.page_allocator`. These must free with the same allocator that allocated. Since we're changing to GPA (see Task 2.4), change to:

```zig
fn freeJobEntry(entry: JobEntry, allocator: std.mem.Allocator) void {
    allocator.free(entry.path);
    allocator.free(entry.content);
    allocator.free(entry.extension);
}

fn freeBinaryEntry(entry: BinaryEntry, allocator: std.mem.Allocator) void {
    allocator.free(entry.path);
    allocator.free(entry.extension);
}
```

Update all call sites in `State.deinit` and `State.removeFile` to pass `self.allocator`.

Also update `runner.zig` defer blocks that free `binary_entries` using `std.heap.page_allocator` (lines 94-95):
```zig
// BEFORE:
std.heap.page_allocator.free(entry.value_ptr.path);
std.heap.page_allocator.free(entry.value_ptr.extension);

// AFTER:
allocator.free(entry.value_ptr.path);
allocator.free(entry.value_ptr.extension);
```

**Step 4: Build**

```bash
zig build 2>&1 | head -20
```

**Step 5: Run tests**

```bash
zig test --dep options -Mroot=src/root.zig -Moptions=src/cli/options_fallback.zig 2>&1 | tail -5
```

**Step 6: Commit**

```bash
git add src/jobs/process.zig src/cli/commands/watch/state.zig src/cli/commands/runner.zig
git commit -m "fix(alloc): replace page_allocator with job.allocator in processFileJob and state"
```

---

### Task 2.3: Per-thread arena allocators in the pool

**Files:**
- Modify: `src/workers/pool.zig`

The pool currently spawns workers that call jobs with no allocator context. We add a per-thread `ArenaAllocator` initialized at thread spawn time.

**Step 1: Modify the worker function**

Current worker signature: `fn worker(pool: *Pool) void`

Add arena initialization:

```zig
fn worker(pool: *Pool) void {
    // Per-thread arena: allocations are fast (no syscall), reset between jobs.
    var arena = std.heap.ArenaAllocator.init(pool.allocator);
    defer arena.deinit();

    pool.mutex.lock();
    defer pool.mutex.unlock();

    // ... existing id tracking code ...

    while (true) {
        while (pool.run_queue.popFirst()) |run_node| {
            pool.mutex.unlock();
            defer pool.mutex.lock();

            const runnable: *Runnable = @fieldParentPtr("node", run_node);
            // Pass the arena allocator into the runnable before calling
            runnable.thread_allocator = arena.allocator();
            runnable.runFn(runnable);

            // Reset arena after each job — O(1), no syscall
            _ = arena.reset(.retain_capacity);
        }

        if (!pool.is_running) break;
        pool.cond.wait(&pool.mutex);
    }
}
```

**Step 2: Thread the arena allocator through Closure**

In `spawnWg`'s `Closure` struct, add `thread_allocator: std.mem.Allocator` and wire it to the job before calling `func`. This requires that `func` accepts a `thread_allocator` param or the Job carries it.

Since `Job` now has `thread_allocator`, the Closure sets `closure.arguments.thread_allocator = closure.thread_allocator` before calling func.

This is the key wiring point — study the existing `Closure.runFn` carefully before modifying.

**Step 3: Build and run tests**

```bash
zig build && zig test --dep options -Mroot=src/root.zig -Moptions=src/cli/options_fallback.zig 2>&1 | tail -5
```

**Step 4: Commit**

```bash
git add src/workers/pool.zig
git commit -m "perf(pool): per-thread arena allocators — 10–50× alloc speed, zero syscalls per job"
```

---

### Task 2.4: GPA in main.zig instead of page_allocator in runner.zig

**Files:**
- Modify: `src/main.zig`
- Modify: `src/cli/commands/runner.zig`
- Modify: `src/cli/commands/watch/exec.zig`

**Step 1: Find all top-level `page_allocator` usage**

```bash
grep -n "page_allocator" src/main.zig src/cli/commands/runner.zig src/cli/commands/watch/exec.zig
```

**Step 2: Initialize GPA in `main.zig`**

```zig
pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    // pass allocator through to exec/execWatch
}
```

**Step 3: Thread allocator through `exec` and `execWatch`**

Change their signatures:
```zig
pub fn exec(cfg: *const Config, cache: ?*CacheImpl, allocator: std.mem.Allocator) !void
pub fn execWatch(cfg: *const Config, cache: ?*CacheImpl, allocator: std.mem.Allocator) !void
```

Remove internal `const allocator = std.heap.page_allocator;` lines.

**Step 4: Build and smoke-test**

```bash
zig build && zig build run -- --path ./src 2>&1 | tail -10
```

**Step 5: Commit**

```bash
git add src/main.zig src/cli/commands/runner.zig src/cli/commands/watch/exec.zig
git commit -m "perf(alloc): use GPA instead of page_allocator throughout runner and watch"
```

---

### Task 2.5: FIFO job queue in pool

**Files:**
- Modify: `src/workers/pool.zig`

**Step 1: Change `prepend` to `append`**

Find in `spawnWg`:
```zig
self.run_queue.prepend(&closure.runnable.node);
```

Change to:
```zig
self.run_queue.append(&closure.runnable.node);
```

`std.SinglyLinkedList.append` puts the node at the tail; `popFirst` takes from the head — giving FIFO order. This matches directory traversal order and improves filesystem cache locality.

Note: `std.SinglyLinkedList` requires O(N) `append`. For large queues this may be slow. If profiling shows this is an issue, switch to `std.DoublyLinkedList` which has O(1) `append` and `popFirst`.

**Step 2: Build and run tests**

```bash
zig build && zig test --dep options -Mroot=src/root.zig -Moptions=src/cli/options_fallback.zig 2>&1 | tail -5
```

**Step 3: Commit**

```bash
git add src/workers/pool.zig
git commit -m "perf(pool): FIFO job queue for better filesystem cache locality"
```

---

## Phase 3 — `zigzag serve` Subcommand

~150 lines. Serves `report.html` + `report-content.json` over HTTP, removing file:// restrictions.

---

### Task 3.1: Create the static file server

**Files:**
- Create: `src/cli/commands/serve.zig`

**Step 1: Write the failing test**

Create `src/cli/commands/serve_test.zig`:

```zig
const std = @import("std");
const serve = @import("serve.zig");

test "deriveMimeType returns correct types" {
    try std.testing.expectEqualStrings("text/html; charset=utf-8", serve.deriveMimeType("report.html"));
    try std.testing.expectEqualStrings("application/json", serve.deriveMimeType("content.json"));
    try std.testing.expectEqualStrings("application/octet-stream", serve.deriveMimeType("unknown.xyz"));
}

test "isPathSafe rejects traversal" {
    try std.testing.expect(!serve.isPathSafe("../etc/passwd"));
    try std.testing.expect(!serve.isPathSafe("/etc/passwd"));
    try std.testing.expect(!serve.isPathSafe("foo/../../etc"));
    try std.testing.expect(serve.isPathSafe("report.html"));
    try std.testing.expect(serve.isPathSafe("report-content.json"));
}
```

Add to `src/root.zig`:
```zig
_ = @import("./cli/commands/serve_test.zig");
```

**Step 2: Run to confirm fails**

```bash
zig test --dep options -Mroot=src/root.zig -Moptions=src/cli/options_fallback.zig 2>&1 | grep "error" | head -5
```

**Step 3: Implement `serve.zig`**

```zig
const std = @import("std");
const builtin = @import("builtin");
const lg = @import("logger.zig");

pub const ServeConfig = struct {
    root_dir: []const u8,
    port: u16 = 8787,
    open_browser: bool = false,
    allocator: std.mem.Allocator,
};

pub fn deriveMimeType(path: []const u8) []const u8 {
    if (std.mem.endsWith(u8, path, ".html")) return "text/html; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".json")) return "application/json";
    if (std.mem.endsWith(u8, path, ".css"))  return "text/css";
    if (std.mem.endsWith(u8, path, ".js"))   return "application/javascript";
    if (std.mem.endsWith(u8, path, ".md"))   return "text/markdown";
    return "application/octet-stream";
}

/// Returns false if the request path would escape the root dir.
pub fn isPathSafe(req_path: []const u8) bool {
    if (req_path.len > 0 and req_path[0] == '/') return false;
    if (std.mem.indexOf(u8, req_path, "..") != null) return false;
    return true;
}

pub fn execServe(cfg: ServeConfig) !void {
    const addr = try std.net.Address.parseIp("127.0.0.1", cfg.port);
    var server = try addr.listen(.{ .reuse_address = true });
    defer server.deinit();

    lg.printSuccess("Serving ZigZag report at \x1b[4mhttp://127.0.0.1:{d}\x1b[0m", .{cfg.port});
    lg.printStep("Root: {s}", .{cfg.root_dir});
    lg.printStep("Press Ctrl+C to stop.", .{});

    if (cfg.open_browser) {
        openBrowser(cfg.allocator, cfg.port);
    }

    while (true) {
        const conn = server.accept() catch continue;
        handleConn(conn, cfg) catch {};
    }
}

fn handleConn(conn: std.net.Server.Connection, cfg: ServeConfig) !void {
    defer conn.stream.close();

    var buf: [4096]u8 = undefined;
    var total: usize = 0;
    while (total < buf.len - 1) {
        const n = try conn.stream.read(buf[total..]);
        if (n == 0) return;
        total += n;
        if (std.mem.indexOf(u8, buf[0..total], "\r\n\r\n") != null) break;
        if (std.mem.indexOf(u8, buf[0..total], "\n\n") != null) break;
    }

    const line_end = std.mem.indexOf(u8, buf[0..total], "\r\n") orelse
        std.mem.indexOf(u8, buf[0..total], "\n") orelse return;
    const first_line = buf[0..line_end];
    if (!std.mem.startsWith(u8, first_line, "GET ")) return;
    const path_end = std.mem.indexOfPos(u8, first_line, 4, " ") orelse first_line.len;
    const req_path_raw = first_line[4..path_end];

    // Strip leading slash and query string
    var req_path = req_path_raw;
    if (req_path.len > 0 and req_path[0] == '/') req_path = req_path[1..];
    if (std.mem.indexOf(u8, req_path, "?")) |q| req_path = req_path[0..q];

    // Default to index
    if (req_path.len == 0) req_path = "report.html";

    // Security: reject path traversal
    if (!isPathSafe(req_path)) {
        try conn.stream.writeAll("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n");
        return;
    }

    const file_path = try std.fs.path.join(cfg.allocator, &.{ cfg.root_dir, req_path });
    defer cfg.allocator.free(file_path);

    const content = std.fs.cwd().readFileAlloc(cfg.allocator, file_path, 64 * 1024 * 1024) catch {
        try conn.stream.writeAll("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n");
        return;
    };
    defer cfg.allocator.free(content);

    const mime = deriveMimeType(req_path);
    var hdr_buf: [256]u8 = undefined;
    const hdr = try std.fmt.bufPrint(
        &hdr_buf,
        "HTTP/1.1 200 OK\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nCache-Control: no-cache\r\n\r\n",
        .{ mime, content.len },
    );
    try conn.stream.writeAll(hdr);
    try conn.stream.writeAll(content);
}

fn openBrowser(allocator: std.mem.Allocator, port: u16) void {
    const url = std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{port}) catch return;
    const t = std.Thread.spawn(.{}, openBrowserThread, .{ allocator, url }) catch {
        allocator.free(url);
        return;
    };
    t.detach();
}

fn openBrowserThread(allocator: std.mem.Allocator, url: []u8) void {
    defer allocator.free(url);
    const argv: []const []const u8 = switch (builtin.os.tag) {
        .macos => &.{ "open", url },
        .windows => &.{ "cmd", "/C", "start", "", url },
        else => &.{ "xdg-open", url },
    };
    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    _ = child.spawnAndWait() catch {};
}
```

**Step 4: Run tests**

```bash
zig test --dep options -Mroot=src/root.zig -Moptions=src/cli/options_fallback.zig 2>&1 | tail -5
```

**Step 5: Commit**

```bash
git add src/cli/commands/serve.zig src/cli/commands/serve_test.zig src/root.zig
git commit -m "feat: add zigzag serve static file server (~150 lines)"
```

---

### Task 3.2: Wire `serve` into the CLI

**Files:**
- Create: `src/cli/handlers/serve.zig`
- Modify: `src/cli/options.zig`
- Modify: `src/main.zig`

**Step 1: Create handler**

`src/cli/handlers/serve.zig`:
```zig
const std = @import("std");
const Config = @import("../commands/config/config.zig").Config;
const serve = @import("../commands/serve.zig");

pub fn handleServe(cfg: *Config, allocator: std.mem.Allocator) !void {
    const root_dir: []const u8 = if (cfg.output_dir) |d| d else "zigzag-reports";
    try serve.execServe(.{
        .root_dir = root_dir,
        .port = cfg.serve_port,
        .open_browser = cfg.open_browser,
        .allocator = allocator,
    });
}
```

**Step 2: Add `open_browser` field to Config**

In `src/cli/commands/config/config.zig`, add:
```zig
open_browser: bool = false,
```

And in `initDefault`:
```zig
.open_browser = false,
```

**Step 3: Add `--open` option to `options.zig`**

Following the existing pattern for boolean flags:
```zig
.{ .name = "--open", .takes_value = false, .handler = handleOpen },
```

`handleOpen` sets `cfg.open_browser = true`.

**Step 4: Handle `serve` subcommand in `main.zig`**

In `main.zig`, alongside the `run` subcommand handling:
```zig
if (std.mem.eql(u8, args[1], "serve")) {
    // Skip "serve" arg, parse remaining for --port, --open, dir
    try handlers.handleServe(&cfg, allocator);
    return;
}
```

**Step 5: Build and test end-to-end**

```bash
zig build
zig build run -- --path ./src --html
./zig-out/bin/zigzag serve --open
```

Expected: browser opens at `http://localhost:8787` showing the dashboard with lazy-loaded content.

**Step 6: Commit**

```bash
git add src/cli/handlers/serve.zig src/cli/options.zig src/main.zig src/cli/commands/config/config.zig
git commit -m "feat(cli): add 'zigzag serve' subcommand and --open flag"
```

---

## Phase 4 — Incremental SSE Payloads

Fixes: watch mode SSE payload from ~1.8 GB → 2–20 KB per file change.

---

### Task 4.1: Replace full-content SSE payload with delta payloads

**Files:**
- Modify: `src/cli/commands/report/writers/sse/sse.zig`
- Modify: `src/cli/commands/report/writers/sse/sse_test.zig`

**Step 1: Write tests for new payload builder**

In `sse_test.zig`:

```zig
test "buildFileDeltaPayload file_update contains type, path, content" {
    const alloc = std.testing.allocator;
    const entry = JobEntry{
        .path = "src/main.zig",
        .content = @constCast("const x = 1;"),
        .size = 12, .mtime = 0, .extension = ".zig", .line_count = 1,
    };
    const payload = try sse.buildFileDeltaPayload(alloc, &entry, .updated);
    defer alloc.free(payload);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, payload, .{});
    defer parsed.deinit();

    try std.testing.expectEqualStrings("file_update", parsed.value.object.get("type").?.string);
    try std.testing.expectEqualStrings("src/main.zig", parsed.value.object.get("path").?.string);
}

test "buildFileDeltaPayload file_delete contains type and path only" {
    const alloc = std.testing.allocator;
    const payload = try sse.buildFileDeletePayload(alloc, "src/deleted.zig");
    defer alloc.free(payload);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, payload, .{});
    defer parsed.deinit();

    try std.testing.expectEqualStrings("file_delete", parsed.value.object.get("type").?.string);
    try std.testing.expectEqualStrings("src/deleted.zig", parsed.value.object.get("path").?.string);
}
```

**Step 2: Run to confirm fails**

```bash
zig test --dep options -Mroot=src/root.zig -Moptions=src/cli/options_fallback.zig 2>&1 | grep "error" | head -5
```

**Step 3: Implement new SSE payload functions in `sse.zig`**

```zig
pub const DeltaKind = enum { updated, created };

/// Build a small delta SSE payload for a single changed/created file.
/// Returns JSON: {"type":"file_update","path":"...","content":"...","meta":{...}}
/// Caller must free.
pub fn buildFileDeltaPayload(
    allocator: std.mem.Allocator,
    entry: *const JobEntry,
    kind: DeltaKind,
) ![]u8 {
    _ = kind; // both map to "file_update" for browser simplicity
    var aw: std.io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    var ws: std.json.Stringify = .{ .writer = &aw.writer, .options = .{} };
    try ws.beginObject();
    try ws.objectField("type"); try ws.write("file_update");
    try ws.objectField("path"); try ws.write(entry.path);
    try ws.objectField("content"); try ws.write(entry.content);
    try ws.objectField("meta");
    try ws.beginObject();
    try ws.objectField("size"); try ws.write(entry.size);
    try ws.objectField("lines"); try ws.write(entry.line_count);
    try ws.objectField("language"); try ws.write(entry.getLanguage());
    try ws.endObject();
    try ws.endObject();
    return allocator.dupe(u8, aw.written());
}

/// Build a delete event payload.
pub fn buildFileDeletePayload(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var aw: std.io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    var ws: std.json.Stringify = .{ .writer = &aw.writer, .options = .{} };
    try ws.beginObject();
    try ws.objectField("type"); try ws.write("file_delete");
    try ws.objectField("path"); try ws.write(path);
    try ws.endObject();
    return allocator.dupe(u8, aw.written());
}
```

**Step 4: Run tests**

```bash
zig test --dep options -Mroot=src/root.zig -Moptions=src/cli/options_fallback.zig 2>&1 | tail -5
```

**Step 5: Commit**

```bash
git add src/cli/commands/report/writers/sse/sse.zig src/cli/commands/report/writers/sse/sse_test.zig
git commit -m "feat(sse): add buildFileDeltaPayload — KB-sized per-file delta events"
```

---

### Task 4.2: Wire delta payloads into watch event loop

**Files:**
- Modify: `src/cli/commands/watch/exec.zig`
- Modify: `src/cli/commands/watch/reporter.zig`

**Step 1: Change event loop to broadcast delta instead of full payload**

In `exec.zig`, in the event loop where `state.updateFile` is called:

```zig
// BEFORE (fires full payload after debounce):
reporter.writeAllReports(state, cfg, sse_server, allocator);

// AFTER: for each changed file, broadcast a delta immediately
switch (event.kind) {
    .created, .modified => {
        state.updateFile(event.path, cache, &pool) catch |err| {
            lg.printError("Failed to process {s}: {s}", .{ event.path, @errorName(err) });
        };
        // Broadcast delta for this specific file
        if (sse_server) |srv| {
            state.entries_mutex.lock();
            const entry_opt = state.file_entries.get(event.path);
            state.entries_mutex.unlock();
            if (entry_opt) |entry| {
                const delta = report.buildFileDeltaPayload(allocator, &entry, .updated) catch null;
                if (delta) |d| {
                    defer allocator.free(d);
                    srv.broadcast(d);
                }
            }
        }
    },
    .deleted => {
        state.removeFile(event.path);
        if (sse_server) |srv| {
            const delta = report.buildFileDeletePayload(allocator, event.path) catch null;
            if (delta) |d| {
                defer allocator.free(d);
                srv.broadcast(d);
            }
        }
    },
}
```

After the debounce quiet period, still write reports to disk (for offline HTML), but SSE already pushed the delta:

```zig
} else if (dirty) {
    for (states.items) |state| {
        reporter.writeAllReports(state, cfg, null, allocator); // null = no SSE here
    }
    dirty = false;
}
```

**Step 2: Update `report.zig` re-exports**

```zig
pub const buildFileDeltaPayload = @import("report/writers/sse/sse.zig").buildFileDeltaPayload;
pub const buildFileDeletePayload = @import("report/writers/sse/sse.zig").buildFileDeletePayload;
```

**Step 3: Update `dashboard.js` to handle delta events**

In the SSE `report` event handler, check `data.type`:

```js
evtSource.addEventListener('report', (e) => {
    const data = JSON.parse(e.data);

    if (data.type === 'file_update') {
        // Patch content cache
        if (_contentCache) _contentCache[data.path] = data.content;
        // Re-render if this file is currently open
        if (currentOpenPath === data.path) openFile(data.path);
        // Update file list metadata
        updateFileMetaInList(data.path, data.meta);
        return;
    }

    if (data.type === 'file_delete') {
        if (_contentCache) delete _contentCache[data.path];
        removeFileFromList(data.path);
        return;
    }

    // Legacy full-update (stats_update or initial load)
    handleFullUpdate(data);
});
```

**Step 4: Build and test**

```bash
zig build
# In one terminal:
zig build run -- --path ./src --html --watch
# In another terminal, touch a file:
touch src/main.zig
```

Watch the terminal — should see the delta logged (KB not GB). Browser should update the open file.

**Step 5: Commit**

```bash
git add src/cli/commands/watch/exec.zig src/cli/commands/report.zig src/templates/src/dashboard.js src/templates/dashboard.html
git commit -m "perf(watch): incremental SSE deltas — per-file KB payloads replace full content map"
```

---

## Phase 5 — Parallel Directory Walk

Fixes: 3–5× faster cold scan for repos with >50k directories.

---

### Task 5.1: Add parallel walk with depth threshold

**Files:**
- Modify: `src/fs/walk.zig`
- Modify: `src/cli/commands/config/config.zig`

**Step 1: Add `walk_threads` config field**

In `config.zig`:
```zig
walk_threads: ?usize = null, // null = auto (max(2, cpu_count/4))
```

In `initDefault`:
```zig
.walk_threads = null,
```

**Step 2: Add a dir-semaphore to `WalkerCtx`**

In `src/walker/context.zig`, add:
```zig
dir_semaphore: *std.Thread.Semaphore,
```

In `runner.zig`, initialize before the walk:
```zig
var dir_sem = std.Thread.Semaphore{ .permits = 64 };
walker_ctx.dir_semaphore = &dir_sem;
```

**Step 3: Implement `walkDirParallel` in `walk.zig`**

```zig
const WALK_DEPTH_THRESHOLD: usize = 3;

pub fn walkDirParallel(
    self: Self,
    path: []const u8,
    depth: usize,
    callback: TProcessWriter,
    ctx: ?*FileContext,
    walker_ctx: *WalkerCtx,
) !void {
    walker_ctx.dir_semaphore.wait(); // acquire open-dir slot
    var dir = std.fs.cwd().openDir(path, .{ .access_sub_paths = true, .iterate = true }) catch {
        walker_ctx.dir_semaphore.post();
        return;
    };
    defer {
        dir.close();
        walker_ctx.dir_semaphore.post();
    }

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (std.mem.eql(u8, entry.name, ".") or std.mem.eql(u8, entry.name, "..")) continue;

        const full_path = try std.fs.path.join(self.allocator, &.{ path, entry.name });

        switch (entry.kind) {
            .file => {
                defer self.allocator.free(full_path);
                try callback(ctx.?, full_path);
            },
            .directory => {
                if (depth < WALK_DEPTH_THRESHOLD) {
                    defer self.allocator.free(full_path);
                    try self.walkDirParallel(full_path, depth + 1, callback, ctx, walker_ctx);
                } else {
                    // Spawn subtree onto pool — path ownership passes to the spawned job
                    const path_owned = full_path; // don't defer free; job owns it
                    walker_ctx.wg.start();
                    walker_ctx.pool.spawnWg(walker_ctx.wg, walkSubtreeJob, .{
                        self, path_owned, depth + 1, callback, ctx, walker_ctx,
                    }) catch {
                        self.allocator.free(path_owned);
                        walker_ctx.wg.finish();
                    };
                }
            },
            else => self.allocator.free(full_path),
        }
    }
}

fn walkSubtreeJob(
    walk_self: Self,
    path: []const u8,
    depth: usize,
    callback: TProcessWriter,
    ctx: ?*FileContext,
    walker_ctx: *WalkerCtx,
) !void {
    defer walk_self.allocator.free(path);
    defer walker_ctx.wg.finish();
    try walk_self.walkDirParallel(path, depth, callback, ctx, walker_ctx);
}
```

**Step 4: Opt in from `runner.zig`**

Replace:
```zig
try walker.walkDir(path, walkerCallback, walk_ctx);
```

With:
```zig
if (cfg.walk_threads != null or true) { // parallel walk always on for now
    try walker.walkDirParallel(path, 0, walkerCallback, walk_ctx, &walker_ctx);
} else {
    try walker.walkDir(path, walkerCallback, walk_ctx);
}
```

And in `state.zig` for watch mode initial scan, same change.

**Step 5: Build and smoke test**

```bash
zig build
time zig build run -- --path ./src 2>&1 | tail -5
```

For a large test, time against a large directory if available.

**Step 6: Run full test suite**

```bash
zig test --dep options -Mroot=src/root.zig -Moptions=src/cli/options_fallback.zig 2>&1 | tail -5
```

**Step 7: Commit**

```bash
git add src/fs/walk.zig src/walker/context.zig src/cli/commands/runner.zig src/cli/commands/config/config.zig src/cli/commands/watch/state.zig
git commit -m "perf(walk): parallel directory traversal with depth threshold — 3–5× faster cold scan"
```

---

## Final Verification

After all phases:

```bash
# Full build
zig build

# All tests
zig test --dep options -Mroot=src/root.zig -Moptions=src/cli/options_fallback.zig

# End-to-end smoke test
zig build run -- --path ./src --html
./zig-out/bin/zigzag serve --open

# Verify output files
ls -lh zigzag-reports/
# Expected: report.md, report.html (small), report-content.json (large)

# Verify report.html doesn't contain source content
grep -c "const " zigzag-reports/report.html
# Expected: 0 (or very low — only template JS, not source files)
```

---

## Performance Targets

| Metric | Before | Target |
|--------|--------|--------|
| Peak RAM (300k files) | 4–8 GB | < 200 MB |
| `report.html` size | 2 GB | < 5 MB |
| Browser initial load | 10–30 s | < 1 s |
| Watch SSE payload | ~1.8 GB | 2–20 KB |
| Walk time (80k dirs) | 3–5 s | ~1 s |
| Alloc speed | 1× | 10–50× |
