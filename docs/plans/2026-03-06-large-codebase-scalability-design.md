# ZigZag Large-Codebase Scalability Design

**Date:** 2026-03-06
**Status:** Approved
**Target:** Repos up to ~300k files (~2 GB source), e.g. Next.js monorepo

---

## Problem Statement

The current pipeline holds all file content in memory simultaneously:

```
walk (sequential) → job queue → N workers → shared StringHashMap → report writer
```

For a 300k-file repo (avg 6 KB/file = ~1.8 GB source), the pipeline produces:

| Buffer | Size |
|--------|------|
| `StringHashMap<JobEntry>` (all content) | ~1.8 GB |
| `writeHtmlReport` metadata JSON | ~200 MB |
| `writeHtmlReport` content map JSON | ~1.8 GB |
| Final HTML assembly buffer | ~2.0 GB |
| **Peak RAM** | **~4–6 GB** (before fragmentation) |

Secondary bottlenecks:
- `walk.zig` recurses sequentially — ~3–5 s for 80k directories
- `processFileJob` calls `std.heap.page_allocator` directly — one `mmap`/`munmap` syscall pair per file allocation → ~600k syscalls for 300k files
- Thread pool queue uses `prepend` (LIFO) — poor cache locality
- Watch mode SSE sends the entire content map on every file change (~1.8 GB per event)

---

## Target Architecture

```
parallel walker (2–4 threads, depth threshold=3)
    ↓
bounded job queue (JOB_QUEUE_CAP = 1024)
    ↓
N worker threads (arena allocator per thread, reset after each job)
    ↓
bounded output queue (OUTPUT_QUEUE_CAP = 1024)
    ↓
single writer thread
    ├── content.json  (streamed, constant memory)
    └── metadata slice (path/size/lines/language, ~36 MB for 300k files)
         ↓
    ReportData aggregation (metadata only)
         ↓
    report.html  (metadata JSON only, no content)
```

**Memory profile:** `O(max_single_file_size + metadata)` — constant regardless of repo size.

### Shutdown ordering (deterministic)

```
walkers finish  (wg_walk.wait())
    ↓
job queue closed
    ↓
workers drain jobs  (wg_workers.wait())
    ↓
output queue closed
    ↓
writer thread finishes JSON  (writer_thread.join())
    ↓
report.html generation
```

This prevents the writer from exiting with incomplete JSON.

### Queue constants

```zig
const JOB_QUEUE_CAP: usize    = 1024; // increase to 4096 for fast NVMe
const OUTPUT_QUEUE_CAP: usize = 1024;
```

---

## Phase Plan

### Phase 1 — Streaming Output + content.json Sidecar

**Goal:** Eliminate the OOM. Memory drops from O(repo_size) to O(max_file_size).

#### Zig changes

**New file: `src/output/writer.zig`**

A `ContentWriter` struct with a bounded queue. A dedicated writer thread drains entries and streams JSON to disk using a comma state machine:

```zig
// Correct JSON object streaming — no trailing comma
try w.writeAll("{");
var first = true;
while (queue.pop()) |entry| {
    if (!first) try w.writeAll(",");
    first = false;
    try writeEntry(w, entry);
    entry.deinit();
}
try w.writeAll("}");
```

Workers back-pressure automatically when the output queue is full.

**Modified: `src/jobs/process.zig`**

Replace `entries_mutex.lock(); file_entries.put(...)` with sending a `ProcessedEntry` (path + content + metadata) to the `ContentWriter` queue. The global `StringHashMap` retains metadata only — content byte slices are NOT stored.

**Modified: `src/cli/commands/report/writers/html/html.zig`**

- Remove `__ZIGZAG_CONTENT__` marker and content buffer.
- Inject metadata JSON only (files array without `content` field).
- Add `deriveContentPath`: `report.html` → `report-content.json`.
- HTML write is now small and fast.

**Modified: `src/cli/commands/runner.zig`**

Adopt the WaitGroup shutdown ordering described above.

#### Browser changes (dashboard.js / template)

Replace `window.CONTENT_MAP = __ZIGZAG_CONTENT__` with lazy fetch:

```js
let _contentCache = null;

async function getContent(path) {
    if (_contentCache) return _contentCache[path];
    if (location.protocol === 'file:') {
        showOfflineMessage();
        return null;
    }
    try {
        const res = await fetch('./report-content.json');
        _contentCache = await res.json();
        return _contentCache[path];
    } catch {
        showOfflineMessage();
        return null;
    }
}
```

`showOfflineMessage()` renders a banner:

> *Source files require a local server to load.*
> *Run `zigzag serve` and open `http://localhost:8787`.*

**Expected outcome:**
- Peak Zig RAM: < 20 MB for 300k files
- Browser initial load: < 1 s (metadata only ~5–20 MB)
- Source loads on demand per file

---

### Phase 2 — Arena Allocators + Fix page_allocator

**Goal:** Eliminate syscalls-per-allocation. 10–50× allocation throughput.

#### Changes

**`src/workers/pool.zig`**

Each worker thread initializes a `std.heap.ArenaAllocator` backed by the GPA at spawn time:

```zig
var arena = std.heap.ArenaAllocator.init(parent_alloc);
defer arena.deinit();

while (nextJob()) |job| {
    defer arena.reset(.retain_capacity);
    processFileJob(arena.allocator(), job);
}
```

`retain_capacity` keeps the OS mapping; subsequent jobs reuse the address space without syscalls.

**`src/jobs/job.zig`**

Add `thread_allocator: std.mem.Allocator` field filled by the pool before dispatch.

**`src/jobs/process.zig`**

Replace every `std.heap.page_allocator` reference with `job.thread_allocator`. Zero `page_allocator` references remain in job code.

**`src/cli/commands/runner.zig`, `src/main.zig`**

Switch from `std.heap.page_allocator` to a `std.heap.GeneralPurposeAllocator` initialized at startup and passed through the call stack.

**`src/workers/pool.zig` — FIFO queue**

Change `run_queue.prepend(...)` → `run_queue.append(...)` (or switch to a doubly-linked list).
FIFO ordering matches directory traversal order → better filesystem prefetch locality.

---

### Phase 3 — `zigzag serve` Subcommand

**Goal:** Zero-friction viewing workflow. Removes file:// CORS restriction.

#### CLI

```
zigzag serve [dir] [--port N] [--open]
```

Defaults: `dir = zigzag-reports/`, `port = 8787`.

#### Implementation

**New file: `src/cli/commands/serve.zig`** (~150 lines)

Static file server built on the existing HTTP infrastructure. Route handler:

```zig
fn handleRequest(path: []const u8, root_dir: []const u8) void {
    // Resolve requested path against root_dir, serve file
    // path traversal: reject any ".." components
    const resolved = std.fs.path.join(allocator, &.{ root_dir, path });
    serveFile(resolved, stream);
}
```

Routes:
- `GET /` → `{dir}/report.html`
- `GET /report-content.json` → `{dir}/report-content.json`
- `GET /<any>` → `{dir}/<any>` (static fallback for future assets)
- Anything not found → 404

Path traversal guard: reject requests containing `..` segments.

**New file: `src/cli/handlers/serve.zig`**

Wires CLI args to `serve.execServe(cfg)`. `--open` calls `openBrowser()` (already exists in `server.zig`).

**Modified: `src/cli/options.zig`**

Add `serve` to the options array.

**CLI output after `zigzag report`:**

```
Report generated.
  report.html      → zigzag-reports/report.html
  content.json     → zigzag-reports/report-content.json

To view:  zigzag serve
```

---

### Phase 4 — Incremental SSE Payloads

**Goal:** Watch mode stays at KB payloads regardless of repo size.

#### Current behavior

`buildSsePayload` serializes the full content map on every file change — potentially gigabytes per SSE event.

#### New payload schema

```json
// Single file changed
{ "type": "file_update", "path": "src/main.zig", "content": "...", "meta": { "size": 4200, "lines": 120, "language": "Zig" } }

// File deleted
{ "type": "file_delete", "path": "src/main.zig" }

// Summary stats changed (new file added, totals changed)
{ "type": "stats_update", "summary": { "source_files": 142, "total_lines": 8900, "languages": [...] } }

// Multiple files changed within debounce window
{ "type": "batch_update", "updates": [ ...file_update items... ] }
```

`batch_update` prevents browser flooding when many files change rapidly (e.g. `git checkout`). The debounce window in `exec.zig` already groups events — the batch payload coalesces them.

#### Browser changes

`dashboard.js` handles all four subtypes on the `report` SSE event:
- `file_update` → patches `_contentCache[path]`, re-renders open file if active
- `file_delete` → removes from cache and file list
- `stats_update` → updates summary panel
- `batch_update` → applies each update sequentially

**Modified: `src/cli/commands/report/writers/sse/sse.zig`**

`buildSsePayload` replaced with `buildFileDeltaPayload(entry, kind)` and `buildBatchPayload(entries)`.

---

### Phase 5 — Parallel Directory Walk

**Goal:** 3–5× faster cold scan for repos with >50k directories.

#### Design

**Modified: `src/fs/walk.zig`**

Add `walkDirParallel` with a depth threshold:

```zig
fn walkDirInternal(path, depth, pool, wg) !void {
    var dir = try openDir(path);
    defer dir.close();

    var it = dir.iterate();
    while (it.next()) |entry| {
        switch (entry.kind) {
            .file => try fileCallback(entry),
            .directory => {
                if (depth < WALK_DEPTH_THRESHOLD) {
                    // Recurse locally — cheap for shallow dirs
                    try walkDirInternal(entry.path, depth + 1, pool, wg);
                } else {
                    // Spawn subtree onto thread pool
                    try pool.spawnWg(wg, walkDirInternal, .{ entry.path, depth + 1, pool, wg });
                }
            },
            else => {},
        }
    }
}

const WALK_DEPTH_THRESHOLD: usize = 3;
```

Depth < 3 recurses locally for cache locality. Depth ≥ 3 spawns tasks — large subtrees fan out across walker threads.

**`src/fs/walk.zig` — open-dir semaphore**

```zig
var dir_semaphore: std.Thread.Semaphore = .{ .permits = 64 };
```

`acquire()` before `openDir`, `release()` in `defer`. Prevents EMFILE on repos with thousands of concurrent open directories.

**`src/cli/commands/config/config.zig`**

Add `walk_threads: ?usize` (default: `@max(2, cpu_count / 4)`).

---

## Expected Performance After Phase 5

| Metric | Before | After |
|--------|--------|-------|
| Peak RAM (300k files) | 4–8 GB | < 200 MB |
| Browser initial load | 10–30 s | < 1 s |
| Walk time (80k dirs) | 3–5 s | ~1 s |
| Allocation speed | 1× (syscall/alloc) | 10–50× (arena) |
| Watch SSE payload | ~1.8 GB | 2–20 KB |
| Offline HTML | Works (embedded) | Graceful fallback |

---

## Files Changed Per Phase

| Phase | New files | Modified files |
|-------|-----------|----------------|
| 1 | `src/output/writer.zig` | `html.zig`, `process.zig`, `runner.zig`, `dashboard.js`, `template.html` |
| 2 | — | `pool.zig`, `process.zig`, `job.zig`, `runner.zig`, `main.zig` |
| 3 | `src/cli/commands/serve.zig`, `src/cli/handlers/serve.zig` | `options.zig` |
| 4 | — | `sse.zig`, `exec.zig`, `dashboard.js` |
| 5 | — | `walk.zig`, `config.zig` |

---

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Writer exits before queue drained | Deterministic WaitGroup shutdown ordering |
| Invalid JSON from writer | Comma state machine (first-entry flag) |
| EMFILE during parallel walk | 64-permit semaphore on `openDir` |
| Path traversal in `zigzag serve` | Reject any request path containing `..` |
| Browser OOM on very large `content.json` (>2 GB) | Future: switch to JSON Lines + streaming parser |
| Queue overflow on fast NVMe | Configurable `JOB_QUEUE_CAP`/`OUTPUT_QUEUE_CAP` |
