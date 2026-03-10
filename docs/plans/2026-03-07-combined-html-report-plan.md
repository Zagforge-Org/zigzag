# Combined Multi-Path HTML Report — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Generate a combined `zigzag-reports/report.html` that aggregates all per-path results into a single grouped dashboard when `--html` is enabled and 2+ paths are configured.

**Architecture:** Split `processPath()` in `runner.zig` into `scanPath()` (returns owned data) and `writePathReports()` (writes per-path files, no cleanup). `exec()` accumulates per-path `ScanResult`s, writes per-path reports, then writes a combined HTML report + merged content sidecar. The combined report uses a separate Zig backend function and a separate TypeScript template — the existing single-path dashboard is untouched.

**Tech Stack:** Zig 0.15.2, TypeScript/esbuild for the template frontend, Python `bundle.py` for template injection.

**Design doc:** `docs/plans/2026-03-07-combined-html-report-design.md`

---

### Task 1: TypeScript — Combined report types

**Files:**
- Create: `src/templates/src/combined-types.ts`

**Step 1: Create the type definitions**

```typescript
// src/templates/src/combined-types.ts

export interface CombinedLanguage {
    name: string;
    files: number;
    lines: number;
    size_bytes: number;
}

export interface CombinedFile {
    path: string;
    root_path: string;
    size: number;
    lines: number;
    language: string;
}

export interface CombinedBinary {
    path: string;
    size: number;
}

export interface CombinedPathSummary {
    source_files: number;
    binary_files: number;
    total_lines: number;
    total_size_bytes: number;
    languages: CombinedLanguage[];
}

export interface CombinedPathReport {
    root_path: string;
    summary: CombinedPathSummary;
    files: CombinedFile[];
    binaries: CombinedBinary[];
}

export interface CombinedGlobalSummary {
    source_files: number;
    binary_files: number;
    total_lines: number;
    total_size_bytes: number;
}

export interface CombinedMeta {
    combined: boolean;
    path_count: number;
    successful_paths: number;
    failed_paths: number;
    file_count: number;
    generated_at: string;
    version: string;
}

export interface CombinedReport {
    meta: CombinedMeta;
    summary: CombinedGlobalSummary;
    paths: CombinedPathReport[];
}

declare global {
    interface Window {
        COMBINED_REPORT: CombinedReport;
    }
}
```

**Step 2: No test needed (types only). Commit.**

```bash
git add src/templates/src/combined-types.ts
git commit -m "feat: add TypeScript types for combined multi-path report"
```

---

### Task 2: TypeScript — combined.ts app logic

**Files:**
- Create: `src/templates/src/combined.ts`

This is the main logic for the combined dashboard. It imports shared modules (`content.ts`, `viewer.ts`, `utils.ts`) but is a separate esbuild entry point from `main.ts`.

**Key behaviors:**
- Render global summary cards (paths, files, lines, size)
- Render per-path collapsible sections (first expanded, rest collapsed)
- Per-path: summary stats + language list + file table (with search)
- Cross-path search filters all sections simultaneously
- Source viewer uses bridge: fetches content via `root_path:path` key, aliases into plain `path` key so viewer.ts can find it

**Step 1: Create combined.ts**

```typescript
// src/templates/src/combined.ts
import { fetchContent, updateContentEntry } from "./content";
import { openViewer, closeViewer } from "./viewer";
import { esc } from "./utils";
import type { CombinedFile, CombinedPathReport } from "./combined-types";

const R = window.COMBINED_REPORT;
const M = R.meta;
const S = R.summary;

// ── Utilities ─────────────────────────────────────────────────────────────────

function fmtSize(bytes: number): string {
    if (bytes < 1024) return bytes + " B";
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
    return (bytes / (1024 * 1024)).toFixed(1) + " MB";
}

// ── Global summary cards ───────────────────────────────────────────────────────

function renderGlobalSummary(): void {
    const cards = document.getElementById("cards")!;
    const items = [
        { label: "Paths",        value: String(M.path_count) },
        { label: "Source Files", value: String(S.source_files) },
        { label: "Binary Files", value: String(S.binary_files) },
        { label: "Total Lines",  value: S.total_lines.toLocaleString() },
        { label: "Total Size",   value: fmtSize(S.total_size_bytes) },
    ];
    cards.innerHTML = items
        .map((c) => `<div class="card"><div class="card-value">${esc(c.value)}</div><div class="card-label">${esc(c.label)}</div></div>`)
        .join("");
}

// ── Search ─────────────────────────────────────────────────────────────────────

let _searchQuery = "";

function matchesSearch(f: CombinedFile, q: string): boolean {
    if (!q) return true;
    const lower = q.toLowerCase();
    return (
        f.path.toLowerCase().includes(lower) ||
        f.root_path.toLowerCase().includes(lower) ||
        f.language.toLowerCase().includes(lower)
    );
}

function filterAllSections(q: string): void {
    _searchQuery = q;
    document.querySelectorAll<HTMLElement>(".path-section").forEach((section) => {
        const rootPath = section.dataset.rootPath!;
        const pathData = R.paths.find((p) => p.root_path === rootPath)!;
        const tbody = section.querySelector<HTMLElement>(".file-tbody")!;
        const count = section.querySelector<HTMLElement>(".path-file-count")!;
        const visible = pathData.files.filter((f) => matchesSearch(f, q));
        count.textContent = visible.length + " / " + pathData.files.length + " files";
        tbody.innerHTML = visible
            .map((f) => renderFileRow(f))
            .join("");
        attachRowListeners(tbody);
    });
}

// ── File rows ─────────────────────────────────────────────────────────────────

function renderFileRow(f: CombinedFile): string {
    return `<tr class="file-row" data-path="${esc(f.path)}" data-root="${esc(f.root_path)}">
        <td>${esc(f.path)}</td>
        <td>${esc(f.language)}</td>
        <td>${f.lines.toLocaleString()}</td>
        <td>${fmtSize(f.size)}</td>
    </tr>`;
}

function attachRowListeners(tbody: HTMLElement): void {
    tbody.querySelectorAll<HTMLElement>(".file-row").forEach((row) => {
        row.addEventListener("click", () => {
            const filePath = row.dataset.path!;
            const rootPath = row.dataset.root!;
            const pathData = R.paths.find((p) => p.root_path === rootPath)!;
            const file = pathData.files.find((f) => f.path === filePath)!;
            openCombinedViewer(file);
        });
    });
}

// ── Source viewer bridge ──────────────────────────────────────────────────────
// Content sidecar keys are "{root_path}:{path}". viewer.ts looks up by file.path.
// Bridge: fetch with combined key, alias into cache under plain path, then open.

function openCombinedViewer(file: CombinedFile): void {
    const contentKey = file.root_path + ":" + file.path;
    fetchContent(contentKey, (src: string) => {
        updateContentEntry(file.path, src);
        openViewer({ path: file.path, size: file.size, lines: file.lines, language: file.language });
    });
}

// ── Per-path sections ─────────────────────────────────────────────────────────

function renderPathSection(p: CombinedPathReport, index: number): string {
    const expanded = index === 0;
    const langRows = p.summary.languages
        .slice(0, 5)
        .map((l) => `<tr><td>${esc(l.name)}</td><td>${l.files}</td><td>${l.lines.toLocaleString()}</td><td>${fmtSize(l.size_bytes)}</td></tr>`)
        .join("");

    const fileRows = p.files.map((f) => renderFileRow(f)).join("");

    return `
<div class="path-section${expanded ? " expanded" : ""}" data-root-path="${esc(p.root_path)}">
    <div class="path-header" role="button" tabindex="0">
        <span class="path-toggle">${expanded ? "▾" : "▸"}</span>
        <span class="path-name">${esc(p.root_path)}</span>
        <span class="path-stats">${p.summary.source_files} files · ${p.summary.total_lines.toLocaleString()} lines · ${fmtSize(p.summary.total_size_bytes)}</span>
    </div>
    <div class="path-body" style="${expanded ? "" : "display:none"}">
        <div class="path-summary-row">
            <div class="card"><div class="card-value">${p.summary.source_files}</div><div class="card-label">Source Files</div></div>
            <div class="card"><div class="card-value">${p.summary.binary_files}</div><div class="card-label">Binary Files</div></div>
            <div class="card"><div class="card-value">${p.summary.total_lines.toLocaleString()}</div><div class="card-label">Total Lines</div></div>
            <div class="card"><div class="card-value">${fmtSize(p.summary.total_size_bytes)}</div><div class="card-label">Total Size</div></div>
        </div>
        ${langRows ? `
        <table class="lang-table">
            <thead><tr><th>Language</th><th>Files</th><th>Lines</th><th>Size</th></tr></thead>
            <tbody>${langRows}</tbody>
        </table>` : ""}
        <p class="path-file-count">${p.files.length} files</p>
        <table class="file-table">
            <thead><tr><th>Path</th><th>Language</th><th>Lines</th><th>Size</th></tr></thead>
            <tbody class="file-tbody">${fileRows}</tbody>
        </table>
    </div>
</div>`;
}

function attachSectionToggle(section: HTMLElement): void {
    const header = section.querySelector<HTMLElement>(".path-header")!;
    header.addEventListener("click", () => {
        const expanded = section.classList.toggle("expanded");
        const toggle = section.querySelector<HTMLElement>(".path-toggle")!;
        const body = section.querySelector<HTMLElement>(".path-body")!;
        toggle.textContent = expanded ? "▾" : "▸";
        body.style.display = expanded ? "" : "none";
    });
    header.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") { e.preventDefault(); header.click(); }
    });
}

// ── Render all path sections ──────────────────────────────────────────────────

function renderPathSections(): void {
    const container = document.getElementById("path-sections")!;
    container.innerHTML = R.paths.map((p, i) => renderPathSection(p, i)).join("");
    container.querySelectorAll<HTMLElement>(".path-section").forEach((section, i) => {
        attachSectionToggle(section);
        attachRowListeners(section.querySelector<HTMLElement>(".file-tbody")!);
    });
}

// ── Keyboard: Escape closes viewer ────────────────────────────────────────────

document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") closeViewer();
});
document.getElementById("viewer-close")?.addEventListener("click", closeViewer);

// ── Search bar ────────────────────────────────────────────────────────────────

const searchEl = document.getElementById("search") as HTMLInputElement | null;
if (searchEl) {
    searchEl.addEventListener("input", () => filterAllSections(searchEl.value.trim()));
}

// ── Header ────────────────────────────────────────────────────────────────────

document.getElementById("report-title")!.textContent =
    "Code Report: " + M.path_count + " paths";
document.getElementById("report-meta")!.textContent =
    "Generated on " + M.generated_at + " · ZigZag v" + M.version +
    (M.failed_paths > 0 ? ` · ⚠ ${M.failed_paths} path(s) failed` : "");

// ── Init ──────────────────────────────────────────────────────────────────────

renderGlobalSummary();
renderPathSections();
```

**Step 2: No test needed at this stage (tested via browser after bundling). Commit.**

```bash
git add src/templates/src/combined-types.ts src/templates/src/combined.ts
git commit -m "feat: add combined dashboard TypeScript app logic"
```

---

### Task 3: HTML shell for combined template

**Files:**
- Create: `src/templates/src/combined.html`

The combined template reuses the same CSS and highlight worker as the single-path template. It adds `path-sections` div and loads `dist/combined.js` instead of `dist/bundle.js`.

**Step 1: Create combined.html**

```html
<!doctype html>
<html lang="en">
    <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width,initial-scale=1" />
        <title>ZigZag Combined Report</title>
        <!-- @inject: dashboard.css -->
        <!-- @inject: prism-theme.css -->
        <style>
        .path-section { border: 1px solid var(--border, #2d3748); border-radius: 6px; margin-bottom: 1.25rem; overflow: hidden; }
        .path-header { display: flex; align-items: center; gap: 0.75rem; padding: 0.9rem 1.25rem; cursor: pointer; background: var(--card-bg, #1a202c); user-select: none; }
        .path-header:hover { background: var(--card-hover, #2d3748); }
        .path-toggle { font-size: 0.9rem; color: var(--accent, #63b3ed); min-width: 1ch; }
        .path-name { font-family: monospace; font-size: 1rem; font-weight: 600; color: var(--text, #e2e8f0); }
        .path-stats { margin-left: auto; font-size: 0.8rem; color: var(--muted, #718096); }
        .path-body { padding: 1.25rem; }
        .path-summary-row { display: flex; gap: 1rem; flex-wrap: wrap; margin-bottom: 1.25rem; }
        .path-summary-row .card { flex: 1; min-width: 100px; }
        .path-file-count { font-size: 0.8rem; color: var(--muted, #718096); margin: 0.5rem 0; }
        .lang-table, .file-table { width: 100%; border-collapse: collapse; font-size: 0.85rem; margin-bottom: 1rem; }
        .lang-table th, .lang-table td, .file-table th, .file-table td { padding: 0.4rem 0.75rem; text-align: left; border-bottom: 1px solid var(--border, #2d3748); }
        .lang-table th, .file-table th { color: var(--muted, #718096); font-weight: 500; }
        .file-row { cursor: pointer; }
        .file-row:hover td { background: var(--row-hover, #2d3748); }
        </style>
    </head>
    <body>
        <header>
            <h1 id="report-title">Code Report</h1>
            <p id="report-meta"></p>
        </header>
        <div class="container">
            <div class="section">
                <h2>Global Summary</h2>
                <div class="cards" id="cards"></div>
            </div>
            <div class="section">
                <h2>Paths</h2>
                <input type="search" id="search" placeholder="Filter by path, language…" />
                <div id="path-sections"></div>
            </div>
        </div>
        <!-- Source viewer slide-in panel (same structure as single-path template) -->
        <div id="viewer">
            <div id="viewer-header">
                <span id="viewer-path"></span>
                <button id="viewer-close" title="Close (Esc)">&#x2715;</button>
            </div>
            <div id="viewer-body"></div>
        </div>
        <!-- Prism highlight worker source -->
        <!-- @inject-text: dist/highlight.worker.js as prism-src -->
        <!-- Combined report data (injected by ZigZag at report-generation time) -->
        <script type="application/json" id="rpt">__ZIGZAG_DATA__</script>
        <script>window.COMBINED_REPORT = JSON.parse(document.getElementById('rpt').textContent);</script>
        <!-- Combined app logic -->
        <!-- @inject: dist/combined.js -->
    </body>
</html>
```

**Step 2: No test at this stage. Commit.**

```bash
git add src/templates/src/combined.html
git commit -m "feat: add combined HTML template shell"
```

---

### Task 4: Extend bundle.py to build combined template

**Files:**
- Modify: `src/templates/bundle.py`

Add an esbuild step for `combined.ts → dist/combined.js` and a second `bundle()` call for `combined.html → combined-dashboard.html`.

**Step 1: Modify `run_esbuild()` to also build combined.js**

In `bundle.py`, find the `run_esbuild()` function. After the block that builds `dist/highlight.worker.js` (around line 135-145), add:

```python
    print("bundle.py: building dist/combined.js...")
    subprocess.run(
        [
            _esbuild_bin(),
            str(TEMPLATES_DIR / "src" / "combined.ts"),
            *esbuild_common,
            f"--outfile={dist_dir / 'combined.js'}",
        ],
        cwd=TEMPLATES_DIR,
        check=True,
    )
```

**Step 2: Modify `__main__` block to also bundle the combined template**

Replace the `if __name__ == "__main__":` block at the bottom:

```python
if __name__ == "__main__":
    run_esbuild()
    bundle()
    bundle(
        template_path=TEMPLATES_DIR / "src" / "combined.html",
        src_dir=TEMPLATES_DIR / "src",
        output_path=TEMPLATES_DIR / "combined-dashboard.html",
        templates_dir=TEMPLATES_DIR,
    )
```

**Step 3: Run the bundler to generate both outputs**

```bash
cd /home/anze/Projects/zigzag/src/templates && python3 bundle.py
```

Expected output (last two lines):
```
Bundled .../src/template.html -> .../dashboard.html (... bytes)
Bundled .../src/combined.html -> .../combined-dashboard.html (... bytes)
```

Verify `combined-dashboard.html` was created:
```bash
ls -la /home/anze/Projects/zigzag/src/templates/combined-dashboard.html
```

**Step 4: Commit**

```bash
cd /home/anze/Projects/zigzag
git add src/templates/bundle.py src/templates/combined-dashboard.html src/templates/dist/combined.js
git commit -m "feat: add combined.ts esbuild step and bundle combined-dashboard.html"
```

---

### Task 5: Zig — ScanResult and processPath() split in runner.zig

**Files:**
- Modify: `src/cli/commands/runner.zig`

**Step 1: Add `ScanResult` struct at the top of runner.zig (after the imports)**

Insert after line 16 (after `const Logger = lg.Logger;`):

```zig
/// Owned result of scanning one path. Caller (exec) controls lifetime.
const ScanResult = struct {
    root_path: []const u8, // not owned — points into cfg.paths item
    file_entries: std.StringHashMap(JobEntry),
    binary_entries: std.StringHashMap(BinaryEntry),
    stats: ProcessStats,

    pub fn deinit(self: *ScanResult, allocator: std.mem.Allocator) void {
        var it = self.file_entries.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.value_ptr.path);
            allocator.free(entry.value_ptr.content);
            allocator.free(entry.value_ptr.extension);
        }
        self.file_entries.deinit();
        var bit = self.binary_entries.iterator();
        while (bit.next()) |entry| {
            allocator.free(entry.value_ptr.path);
            allocator.free(entry.value_ptr.extension);
        }
        self.binary_entries.deinit();
    }
};
```

**Step 2: Rename `processPath` → `scanPath` and change its return type**

Replace the entire `processPath` function with two functions: `scanPath` and `writePathReports`.

`scanPath` is identical to the first half of the old `processPath` (up to `wg.wait()` and the logger loop), but instead of writing any reports, it returns a `ScanResult`.

The old `processPath` signature was:
```zig
fn processPath(cfg, cache, path, pool, allocator, logger) !void
```

New `scanPath`:
```zig
fn scanPath(
    cfg: *const Config,
    cache: ?*CacheImpl,
    path: []const u8,
    pool: *Pool,
    allocator: std.mem.Allocator,
    logger: ?*Logger,
) !ScanResult {
    if (path.len != 0) {
        lg.printStep("Processing path: {s}", .{path});
        if (logger) |l| l.log("Processing path: {s}", .{path});
    }

    var dir = std.fs.cwd().openDir(path, .{}) catch {
        return error.NotADirectory;
    };
    defer dir.close();

    const output_filename: []const u8 = if (cfg.output) |o| o else "report.md";
    const md_path = try report.resolveOutputPath(allocator, cfg, path, output_filename);
    defer allocator.free(md_path);

    var file_ctx = FileContext{
        .ignore_list = .{},
        .md = undefined,
        .md_mutex = undefined,
    };
    defer file_ctx.ignore_list.deinit(allocator);

    const base_output_dir: []const u8 = if (cfg.output_dir) |d| d else "zigzag-reports";
    const output_dir_ignore = try allocator.dupe(u8, base_output_dir);
    try file_ctx.ignore_list.append(allocator, output_dir_ignore);

    const owned_md_path = try allocator.dupe(u8, md_path);
    try file_ctx.ignore_list.append(allocator, owned_md_path);

    if (cfg.json_output) {
        const json_ignore = try report.deriveJsonPath(allocator, md_path);
        try file_ctx.ignore_list.append(allocator, json_ignore);
    }
    if (cfg.html_output) {
        const html_ignore = try report.deriveHtmlPath(allocator, md_path);
        try file_ctx.ignore_list.append(allocator, html_ignore);
        const content_ignore = try report.deriveContentPath(allocator, html_ignore);
        try file_ctx.ignore_list.append(allocator, content_ignore);
    }
    if (cfg.llm_report) {
        const llm_ignore = try report.deriveLlmPath(allocator, md_path);
        try file_ctx.ignore_list.append(allocator, llm_ignore);
    }
    for (cfg.ignore_patterns.items) |pattern| {
        const owned_pattern = try allocator.dupe(u8, pattern);
        try file_ctx.ignore_list.append(allocator, owned_pattern);
    }

    var wg = WaitGroup.init();
    var stats = ProcessStats.init();

    var file_entries = std.StringHashMap(JobEntry).init(allocator);
    var binary_entries = std.StringHashMap(BinaryEntry).init(allocator);

    var entries_mutex = std.Thread.Mutex{};
    var walker_ctx = WalkerCtx{
        .pool = pool,
        .wg = &wg,
        .file_ctx = &file_ctx,
        .cache = cache,
        .stats = &stats,
        .file_entries = &file_entries,
        .binary_entries = &binary_entries,
        .entries_mutex = &entries_mutex,
        .allocator = allocator,
    };

    const walker = try walk.init(allocator);
    const walk_ctx: ?*FileContext = @ptrCast(@alignCast(&walker_ctx));
    try walker.walkDir(path, walkerCallback, walk_ctx);
    wg.wait();

    if (logger) |l| {
        var it = file_entries.iterator();
        while (it.next()) |entry| {
            l.log("  file: {s} ({d} bytes, {d} lines)", .{
                entry.value_ptr.path,
                entry.value_ptr.content.len,
                entry.value_ptr.line_count,
            });
        }
    }

    return .{
        .root_path = path,
        .file_entries = file_entries,
        .binary_entries = binary_entries,
        .stats = stats,
    };
}
```

**Step 3: Add `writePathReports` function**

```zig
fn writePathReports(
    result: *const ScanResult,
    cfg: *const Config,
    pool: *Pool,
    allocator: std.mem.Allocator,
    logger: ?*Logger,
) !void {
    _ = pool; // reserved for future use

    const output_filename: []const u8 = if (cfg.output) |o| o else "report.md";
    const md_path = try report.resolveOutputPath(allocator, cfg, result.root_path, output_filename);
    defer allocator.free(md_path);

    if (cfg.html_output) {
        const html_path_for_content = try report.deriveHtmlPath(allocator, md_path);
        defer allocator.free(html_path_for_content);
        const content_path = try report.deriveContentPath(allocator, html_path_for_content);
        defer allocator.free(content_path);
        try report.writeContentJson(&result.file_entries, content_path, allocator);
        lg.printSuccess("Content JSON:  {s}", .{content_path});
        if (logger) |l| l.log("Content JSON written: {s}", .{content_path});
    }

    var report_data = try report.ReportData.init(allocator, &result.file_entries, &result.binary_entries, cfg.timezone_offset);
    defer report_data.deinit();

    try report.writeReport(&report_data, &result.file_entries, md_path, result.root_path, cfg, allocator);
    lg.printSuccess("Report written: {s}", .{md_path});
    if (logger) |l| l.log("Report written: {s}", .{md_path});

    if (cfg.json_output) {
        const json_path = try report.deriveJsonPath(allocator, md_path);
        defer allocator.free(json_path);
        try report.writeJsonReport(&report_data, json_path, result.root_path, cfg, allocator);
        lg.printSuccess("JSON report: {s}", .{json_path});
        if (logger) |l| l.log("JSON report written: {s}", .{json_path});
    }

    if (cfg.html_output) {
        const html_path = try report.deriveHtmlPath(allocator, md_path);
        defer allocator.free(html_path);
        try report.writeHtmlReport(&report_data, html_path, result.root_path, cfg, allocator);
        lg.printSuccess("HTML report: {s}", .{html_path});
        if (logger) |l| l.log("HTML report written: {s}", .{html_path});
    }

    if (cfg.llm_report) {
        const llm_path = try report.deriveLlmPath(allocator, md_path);
        defer allocator.free(llm_path);
        try report.writeLlmReport(&report_data, result.binary_entries.count(), llm_path, result.root_path, cfg, allocator);
        lg.printSuccess("LLM report: {s}", .{llm_path});
        if (logger) |l| l.log("LLM report written: {s}", .{llm_path});
    }

    const sv = result.stats.getSummary();
    lg.printSummary(result.root_path, sv.total, sv.source, sv.cached, sv.processed, sv.binary, sv.ignored);
    if (logger) |l| {
        l.log("Summary: total={d}, source={d}, cached={d}, fresh={d}, binary={d}, ignored={d}", .{
            sv.total, sv.source, sv.cached, sv.processed, sv.binary, sv.ignored,
        });
    }
}
```

**Step 4: Build to verify it compiles**

```bash
cd /home/anze/Projects/zigzag && zig build 2>&1 | head -40
```

Expected: no errors. Fix any compilation errors before continuing.

**Step 5: Commit**

```bash
git add src/cli/commands/runner.zig
git commit -m "refactor: split processPath into scanPath + writePathReports with ScanResult"
```

---

### Task 6: Zig — writeCombinedContentJson with collision-safe keys

**Files:**
- Modify: `src/cli/commands/report/writers/html/html.zig`
- Modify: `src/cli/commands/report/writers/html/html_test.zig`

**Step 1: Write the failing test first**

Add to the end of `html_test.zig`:

```zig
const writeCombinedContentJson = @import("./html.zig").writeCombinedContentJson;
const CombinedContentPath = @import("./html.zig").CombinedContentPath;

test "writeCombinedContentJson uses root_path:path as key to avoid collisions" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const out_path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(out_path);
    const content_path = try std.fs.path.join(alloc, &.{ out_path, "combined-content.json" });
    defer alloc.free(content_path);

    // Two paths each with a file at "src/main.zig"
    var entries_a = std.StringHashMap(JobEntry).init(alloc);
    defer entries_a.deinit();
    const ca: []u8 = try alloc.dupe(u8, "backend content");
    defer alloc.free(ca);
    try entries_a.put("src/main.zig", .{ .path = "src/main.zig", .content = ca, .size = 15, .mtime = 0, .extension = ".zig", .line_count = 1 });

    var entries_b = std.StringHashMap(JobEntry).init(alloc);
    defer entries_b.deinit();
    const cb: []u8 = try alloc.dupe(u8, "frontend content");
    defer alloc.free(cb);
    try entries_b.put("src/main.zig", .{ .path = "src/main.zig", .content = cb, .size = 16, .mtime = 0, .extension = ".zig", .line_count = 1 });

    const paths = [_]CombinedContentPath{
        .{ .root_path = "./backend", .file_entries = &entries_a },
        .{ .root_path = "./frontend", .file_entries = &entries_b },
    };
    try writeCombinedContentJson(&paths, content_path, alloc);

    const written = try std.fs.cwd().readFileAlloc(alloc, content_path, 1024 * 1024);
    defer alloc.free(written);

    // Both keys must be present — no collision
    try std.testing.expect(std.mem.indexOf(u8, written, "./backend:src/main.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "./frontend:src/main.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "backend content") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "frontend content") != null);
}

test "writeCombinedContentJson produces valid JSON with two paths" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const out_path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(out_path);
    const content_path = try std.fs.path.join(alloc, &.{ out_path, "combined-content.json" });
    defer alloc.free(content_path);

    var entries_a = std.StringHashMap(JobEntry).init(alloc);
    defer entries_a.deinit();
    const ca: []u8 = try alloc.dupe(u8, "hello");
    defer alloc.free(ca);
    try entries_a.put("a.zig", .{ .path = "a.zig", .content = ca, .size = 5, .mtime = 0, .extension = ".zig", .line_count = 1 });

    var entries_b = std.StringHashMap(JobEntry).init(alloc);
    defer entries_b.deinit();
    const cb: []u8 = try alloc.dupe(u8, "world");
    defer alloc.free(cb);
    try entries_b.put("b.zig", .{ .path = "b.zig", .content = cb, .size = 5, .mtime = 0, .extension = ".zig", .line_count = 1 });

    const paths = [_]CombinedContentPath{
        .{ .root_path = "./src", .file_entries = &entries_a },
        .{ .root_path = "./lib", .file_entries = &entries_b },
    };
    try writeCombinedContentJson(&paths, content_path, alloc);

    const written = try std.fs.cwd().readFileAlloc(alloc, content_path, 1024 * 1024);
    defer alloc.free(written);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, written, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(std.json.Value.object, std.meta.activeTag(parsed.value));
    try std.testing.expectEqual(@as(usize, 2), parsed.value.object.count());
}
```

**Step 2: Run the test to verify it fails**

```bash
zig test --dep options -Mroot=src/root.zig -Moptions=src/cli/options_fallback.zig 2>&1 | grep -A5 "writeCombinedContentJson"
```

Expected: compilation error — `writeCombinedContentJson` not found.

**Step 3: Implement `writeCombinedContentJson` in html.zig**

Add after the existing `writeContentJson` function (around line 178):

```zig
/// Per-path entry for the combined content writer.
pub const CombinedContentPath = struct {
    root_path: []const u8,
    file_entries: *const std.StringHashMap(JobEntry),
};

/// Write a merged content sidecar for the combined report.
/// Keys use the format "{root_path}:{relative_path}" to prevent collisions
/// when two scanned paths contain files with the same relative path.
pub fn writeCombinedContentJson(
    paths: []const CombinedContentPath,
    content_path: []const u8,
    allocator: std.mem.Allocator,
) !void {
    var file = try std.fs.cwd().createFile(content_path, .{ .truncate = true });
    defer file.close();

    try file.writeAll("{");
    var first = true;
    for (paths) |p| {
        var it = p.file_entries.iterator();
        while (it.next()) |kv| {
            if (!first) try file.writeAll(",");
            first = false;

            // Key: "{root_path}:{path}"
            const combined_key = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ p.root_path, kv.key_ptr.* });
            defer allocator.free(combined_key);

            var key_aw: std.io.Writer.Allocating = .init(allocator);
            defer key_aw.deinit();
            var kws: std.json.Stringify = .{ .writer = &key_aw.writer, .options = .{} };
            try kws.write(combined_key);
            try file.writeAll(key_aw.written());

            try file.writeAll(":");

            var val_aw: std.io.Writer.Allocating = .init(allocator);
            defer val_aw.deinit();
            var vws: std.json.Stringify = .{ .writer = &val_aw.writer, .options = .{} };
            try vws.write(kv.value_ptr.content);
            try file.writeAll(val_aw.written());
        }
    }
    try file.writeAll("}");
}
```

**Step 4: Run tests and confirm they pass**

```bash
zig test --dep options -Mroot=src/root.zig -Moptions=src/cli/options_fallback.zig 2>&1 | tail -20
```

Expected: all tests pass, including the two new `writeCombinedContentJson` tests.

**Step 5: Commit**

```bash
git add src/cli/commands/report/writers/html/html.zig src/cli/commands/report/writers/html/html_test.zig
git commit -m "feat: add writeCombinedContentJson with root_path:path collision-safe keys"
```

---

### Task 7: Zig — writeCombinedHtmlReport

**Files:**
- Modify: `src/cli/commands/report/writers/html/html.zig`
- Modify: `src/cli/commands/report/writers/html/html_test.zig`

**Step 1: Write the failing tests first**

Add to `html_test.zig`:

```zig
const writeCombinedHtmlReport = @import("./html.zig").writeCombinedHtmlReport;
const CombinedPathData = @import("./html.zig").CombinedPathData;

test "writeCombinedHtmlReport creates file with combined:true in JSON" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);
    const html_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.html" });
    defer alloc.free(html_path);

    var file_entries_a = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries_a.deinit();
    var binary_entries_a = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries_a.deinit();

    var file_entries_b = std.StringHashMap(JobEntry).init(alloc);
    defer file_entries_b.deinit();
    var binary_entries_b = std.StringHashMap(BinaryEntry).init(alloc);
    defer binary_entries_b.deinit();

    var data_a = try ReportData.init(alloc, &file_entries_a, &binary_entries_a, null);
    defer data_a.deinit();
    var data_b = try ReportData.init(alloc, &file_entries_b, &binary_entries_b, null);
    defer data_b.deinit();

    var cfg = Config.default(alloc);
    defer cfg.deinit();

    const paths = [_]CombinedPathData{
        .{ .root_path = "./src", .data = &data_a },
        .{ .root_path = "./lib", .data = &data_b },
    };
    try writeCombinedHtmlReport(&paths, html_path, 0, &cfg, alloc);

    const content = try tmp.dir.readFileAlloc(alloc, "report.html", 4 << 20);
    defer alloc.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "<!doctype html>") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"combined\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"path_count\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "window.COMBINED_REPORT") != null);
}

test "writeCombinedHtmlReport includes root_path for each path section" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);
    const html_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.html" });
    defer alloc.free(html_path);

    var fe = std.StringHashMap(JobEntry).init(alloc);
    defer fe.deinit();
    var be = std.StringHashMap(BinaryEntry).init(alloc);
    defer be.deinit();

    var data = try ReportData.init(alloc, &fe, &be, null);
    defer data.deinit();

    var cfg = Config.default(alloc);
    defer cfg.deinit();

    const paths = [_]CombinedPathData{
        .{ .root_path = "./myproject", .data = &data },
        .{ .root_path = "./myproject/tests", .data = &data },
    };
    try writeCombinedHtmlReport(&paths, html_path, 0, &cfg, alloc);

    const content = try tmp.dir.readFileAlloc(alloc, "report.html", 4 << 20);
    defer alloc.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "./myproject") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "./myproject/tests") != null);
}

test "writeCombinedHtmlReport not generated when paths empty" {
    // This test verifies the generation condition is enforced at call sites,
    // but also tests that the function handles 0 paths gracefully.
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);
    const html_path = try std.fs.path.join(alloc, &.{ tmp_path, "report.html" });
    defer alloc.free(html_path);

    var cfg = Config.default(alloc);
    defer cfg.deinit();

    const paths: []const CombinedPathData = &.{};
    try writeCombinedHtmlReport(paths, html_path, 0, &cfg, alloc);

    const content = try tmp.dir.readFileAlloc(alloc, "report.html", 4 << 20);
    defer alloc.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "\"path_count\":0") != null);
}
```

**Step 2: Run tests — expect compilation failure**

```bash
zig test --dep options -Mroot=src/root.zig -Moptions=src/cli/options_fallback.zig 2>&1 | grep -A3 "writeCombinedHtmlReport\|CombinedPathData"
```

**Step 3: Implement `writeCombinedHtmlReport` in html.zig**

Add the `@embedFile` at the top of `html.zig` (after the existing `dashboard_template` embedFile, around line 7):

```zig
const combined_dashboard_template = @embedFile("../../../../../templates/combined-dashboard.html");
```

Then add the struct and function after `writeCombinedContentJson`:

```zig
/// Per-path entry for the combined HTML report writer.
pub const CombinedPathData = struct {
    root_path: []const u8,
    data: *const ReportData,
};

/// Write a combined multi-path HTML dashboard to html_path.
/// Uses the combined-dashboard.html template (separate from the single-path template).
pub fn writeCombinedHtmlReport(
    paths: []const CombinedPathData,
    html_path: []const u8,
    failed_paths: usize,
    cfg: *const Config,
    allocator: std.mem.Allocator,
) !void {
    const marker = "__ZIGZAG_DATA__";
    const split_pos = std.mem.indexOf(u8, combined_dashboard_template, marker) orelse
        return error.MissingTemplateMarker;

    // --- Compute global totals ---
    var total_files: usize = 0;
    var total_binary: usize = 0;
    var total_lines: usize = 0;
    var total_size: u64 = 0;
    for (paths) |p| {
        total_files += p.data.sorted_files.items.len;
        total_binary += p.data.sorted_binaries.items.len;
        total_lines += p.data.total_lines;
        total_size += p.data.total_size;
    }

    // Use timestamp from first path (or generate fresh if empty)
    const generated_at: []const u8 = if (paths.len > 0)
        paths[0].data.generated_at_str
    else
        "unknown";

    // --- Build combined JSON ---
    var json_aw: std.io.Writer.Allocating = .init(allocator);
    defer json_aw.deinit();

    var ws: std.json.Stringify = .{ .writer = &json_aw.writer, .options = .{} };
    try ws.beginObject();

    // meta
    try ws.objectField("meta");
    try ws.beginObject();
    try ws.objectField("combined");
    try ws.write(true);
    try ws.objectField("path_count");
    try ws.write(paths.len);
    try ws.objectField("successful_paths");
    try ws.write(paths.len);
    try ws.objectField("failed_paths");
    try ws.write(failed_paths);
    try ws.objectField("file_count");
    try ws.write(total_files);
    try ws.objectField("generated_at");
    try ws.write(generated_at);
    try ws.objectField("version");
    try ws.write(cfg.version);
    try ws.endObject();

    // global summary
    try ws.objectField("summary");
    try ws.beginObject();
    try ws.objectField("source_files");
    try ws.write(total_files);
    try ws.objectField("binary_files");
    try ws.write(total_binary);
    try ws.objectField("total_lines");
    try ws.write(total_lines);
    try ws.objectField("total_size_bytes");
    try ws.write(total_size);
    try ws.endObject();

    // paths array
    try ws.objectField("paths");
    try ws.beginArray();
    for (paths) |p| {
        try ws.beginObject();

        try ws.objectField("root_path");
        try ws.write(p.root_path);

        // per-path summary
        try ws.objectField("summary");
        try ws.beginObject();
        try ws.objectField("source_files");
        try ws.write(p.data.sorted_files.items.len);
        try ws.objectField("binary_files");
        try ws.write(p.data.sorted_binaries.items.len);
        try ws.objectField("total_lines");
        try ws.write(p.data.total_lines);
        try ws.objectField("total_size_bytes");
        try ws.write(p.data.total_size);
        try ws.objectField("languages");
        try ws.beginArray();
        for (p.data.lang_list.items) |ls| {
            try ws.beginObject();
            try ws.objectField("name");
            try ws.write(ls.name);
            try ws.objectField("files");
            try ws.write(ls.files);
            try ws.objectField("lines");
            try ws.write(ls.lines);
            try ws.objectField("size_bytes");
            try ws.write(ls.size_bytes);
            try ws.endObject();
        }
        try ws.endArray();
        try ws.endObject(); // summary

        // files (include root_path in each entry)
        try ws.objectField("files");
        try ws.beginArray();
        for (p.data.sorted_files.items) |e| {
            try ws.beginObject();
            try ws.objectField("path");
            try ws.write(e.path);
            try ws.objectField("root_path");
            try ws.write(p.root_path);
            try ws.objectField("size");
            try ws.write(e.size);
            try ws.objectField("lines");
            try ws.write(e.line_count);
            try ws.objectField("language");
            try ws.write(e.getLanguage());
            try ws.endObject();
        }
        try ws.endArray();

        // binaries
        try ws.objectField("binaries");
        try ws.beginArray();
        for (p.data.sorted_binaries.items) |b| {
            try ws.beginObject();
            try ws.objectField("path");
            try ws.write(b.path);
            try ws.objectField("size");
            try ws.write(b.size);
            try ws.endObject();
        }
        try ws.endArray();

        try ws.endObject(); // path entry
    }
    try ws.endArray(); // paths

    try ws.endObject(); // root

    const json_raw = json_aw.written();
    const json_safe = try std.mem.replaceOwned(u8, allocator, json_raw, "</script>", "<\\/script>");
    defer allocator.free(json_safe);

    var aw: std.io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    try aw.writer.writeAll(combined_dashboard_template[0..split_pos]);
    try aw.writer.writeAll(json_safe);
    try aw.writer.writeAll(combined_dashboard_template[split_pos + marker.len ..]);

    var html_file = try std.fs.cwd().createFile(html_path, .{ .truncate = true });
    defer html_file.close();
    try html_file.writeAll(aw.written());
}
```

**Step 4: Run tests**

```bash
zig test --dep options -Mroot=src/root.zig -Moptions=src/cli/options_fallback.zig 2>&1 | tail -20
```

Expected: all tests pass including the three new `writeCombinedHtmlReport` tests.

**Step 5: Full build check**

```bash
zig build 2>&1 | head -20
```

Expected: no errors.

**Step 6: Commit**

```bash
git add src/cli/commands/report/writers/html/html.zig src/cli/commands/report/writers/html/html_test.zig
git commit -m "feat: add writeCombinedHtmlReport and CombinedPathData types"
```

---

### Task 8: Update report.zig facade

**Files:**
- Modify: `src/cli/commands/report.zig`

**Step 1: Add exports for combined functions**

Append to `report.zig`:

```zig
pub const writeCombinedHtmlReport = @import("report/writers/html/html.zig").writeCombinedHtmlReport;
pub const writeCombinedContentJson = @import("report/writers/html/html.zig").writeCombinedContentJson;
pub const CombinedPathData = @import("report/writers/html/html.zig").CombinedPathData;
pub const CombinedContentPath = @import("report/writers/html/html.zig").CombinedContentPath;
```

**Step 2: Build to verify**

```bash
zig build 2>&1 | head -10
```

**Step 3: Commit**

```bash
git add src/cli/commands/report.zig
git commit -m "feat: export combined report functions from report.zig facade"
```

---

### Task 9: Update exec() in runner.zig to generate combined report

**Files:**
- Modify: `src/cli/commands/runner.zig`

This is the core orchestration change. Replace the existing `exec()` function body.

**Step 1: Update the `exec()` function**

Replace the body of `exec()` (everything after the pool init, currently lines ~207-234) with:

```zig
pub fn exec(cfg: *const Config, cache: ?*CacheImpl, allocator: std.mem.Allocator) !void {
    if (cfg.paths.items.len == 0) return;

    var logger_storage: ?Logger = null;
    defer if (logger_storage) |*l| l.deinit();
    if (cfg.log) {
        const output_dir: []const u8 = if (cfg.output_dir) |d| d else "zigzag-reports";
        if (Logger.init(output_dir, allocator)) |l| {
            logger_storage = l;
        } else |err| {
            lg.printWarn("Could not create log file: {s}", .{@errorName(err)});
        }
    }
    const logger: ?*Logger = if (logger_storage) |*l| l else null;

    if (logger) |l| l.log("zigzag started — processing {d} path(s)", .{cfg.paths.items.len});

    var pool = Pool{};
    try pool.init(.{
        .allocator = allocator,
        .n_jobs = cfg.n_threads,
    });
    defer pool.deinit();

    lg.printStep("Processing {d} path(s)...", .{cfg.paths.items.len});

    const multi_html = cfg.html_output and cfg.paths.items.len > 1;

    // Accumulate results when a combined report is needed.
    var combined_results: std.ArrayList(ScanResult) = .empty;
    var combined_datas: std.ArrayList(report.ReportData) = .empty;
    defer {
        for (combined_datas.items) |*d| d.deinit();
        combined_datas.deinit(allocator);
        for (combined_results.items) |*r| r.deinit(allocator);
        combined_results.deinit(allocator);
    }

    var failed_paths: usize = 0;

    for (cfg.paths.items) |path| {
        var result = scanPath(cfg, cache, path, &pool, allocator, logger) catch |err| {
            switch (err) {
                error.NotADirectory => {
                    lg.printError("Path '{s}' is not a directory", .{path});
                    if (logger) |l| l.log("ERROR: Path '{s}' is not a directory", .{path});
                },
                else => {
                    lg.printError("Unexpected error processing '{s}': {s}", .{ path, @errorName(err) });
                    if (logger) |l| l.log("ERROR: {s}", .{@errorName(err) });
                },
            }
            failed_paths += 1;
            continue;
        };

        writePathReports(&result, cfg, &pool, allocator, logger) catch |err| {
            lg.printError("Error writing reports for '{s}': {s}", .{ path, @errorName(err) });
            if (logger) |l| l.log("ERROR writing reports: {s}", .{@errorName(err)});
        };

        if (multi_html) {
            // Build ReportData here so it can be reused for the combined report.
            const rd = try report.ReportData.init(allocator, &result.file_entries, &result.binary_entries, cfg.timezone_offset);
            try combined_results.append(allocator, result);
            try combined_datas.append(allocator, rd);
        } else {
            result.deinit(allocator);
        }
    }

    // Write combined HTML report when multiple paths are configured.
    if (multi_html and combined_results.items.len > 1) {
        const base_output_dir: []const u8 = if (cfg.output_dir) |d| d else "zigzag-reports";
        try std.fs.cwd().makePath(base_output_dir);

        // Build CombinedPathData slice (borrows from combined_results + combined_datas)
        var path_data_list: std.ArrayList(report.CombinedPathData) = .empty;
        defer path_data_list.deinit(allocator);
        for (combined_results.items, combined_datas.items) |r, *d| {
            try path_data_list.append(allocator, .{ .root_path = r.root_path, .data = d });
        }

        const combined_html_path = try std.fmt.allocPrint(allocator, "{s}/report.html", .{base_output_dir});
        defer allocator.free(combined_html_path);
        try report.writeCombinedHtmlReport(path_data_list.items, combined_html_path, failed_paths, cfg, allocator);
        lg.printSuccess("Combined HTML: {s}", .{combined_html_path});
        if (logger) |l| l.log("Combined HTML report written: {s}", .{combined_html_path});

        // Build CombinedContentPath slice
        var content_path_list: std.ArrayList(report.CombinedContentPath) = .empty;
        defer content_path_list.deinit(allocator);
        for (combined_results.items) |r| {
            try content_path_list.append(allocator, .{ .root_path = r.root_path, .file_entries = &r.file_entries });
        }

        const combined_content_path = try std.fmt.allocPrint(allocator, "{s}/report-content.json", .{base_output_dir});
        defer allocator.free(combined_content_path);
        try report.writeCombinedContentJson(content_path_list.items, combined_content_path, allocator);
        lg.printSuccess("Combined Content: {s}", .{combined_content_path});
        if (logger) |l| l.log("Combined content JSON written: {s}", .{combined_content_path});
    }

    lg.printSuccess("All paths processed!", .{});
    if (logger) |l| l.log("Done", .{});
}
```

**Step 2: Build to check compilation**

```bash
zig build 2>&1 | head -30
```

Fix any errors. Common issues:
- `combined_results` and `combined_datas` deferred cleanup order: `datas` must be deferred before `results` (Zig runs defers in reverse). ✓ Already correct in the code above.
- `writePathReports` no longer computes `ReportData` — but the current `writePathReports` in Task 5 does compute it internally. Note: in the combined case, we compute `ReportData` **twice** for a path (once in `writePathReports`, once in `exec` for the combined report). This is acceptable for MVP. A future optimization could return `ReportData` from `writePathReports`.

**Step 3: Run tests**

```bash
zig test --dep options -Mroot=src/root.zig -Moptions=src/cli/options_fallback.zig 2>&1 | tail -20
```

Expected: all tests pass.

**Step 4: Smoke test manually with two paths**

Create a minimal `zig.conf.json` in a temp dir with two paths, or run with explicit flags:

```bash
zig build run -- --path src --path src/cli --html
```

Verify:
- `zigzag-reports/src/report.html` exists
- `zigzag-reports/src/cli/report.html` exists (or the correct path segment)
- `zigzag-reports/report.html` exists (combined)
- `zigzag-reports/report-content.json` exists (combined content)
- Open `zigzag-reports/report.html` in a browser via `zigzag serve` and verify the two-path sections render correctly

**Step 5: Test single-path case to confirm no regression**

```bash
zig build run -- --path src --html
```

Verify: only `zigzag-reports/src/report.html` is generated. No `zigzag-reports/report.html`.

**Step 6: Commit**

```bash
git add src/cli/commands/runner.zig
git commit -m "feat: generate combined HTML report when multiple paths configured with --html"
```

---

### Task 10: Add combined output paths to ignore list (correctness fix)

**Files:**
- Modify: `src/cli/commands/runner.zig`

In `scanPath()`, the ignore list is built from the per-path output. The combined report lives at `zigzag-reports/report.html` and `zigzag-reports/report-content.json`. Since `zigzag-reports/` is already added to the ignore list (as `base_output_dir`), these combined outputs are already ignored automatically.

**Step 1: Verify this is the case**

Check `scanPath()` — it adds `base_output_dir` (i.e. `"zigzag-reports"`) to the ignore list. Since both combined outputs are inside `zigzag-reports/`, no additional ignore entries are needed.

If this is confirmed, no code change is needed. Document this conclusion in a code comment in `exec()`:

```zig
// Note: combined outputs (zigzag-reports/report.html, zigzag-reports/report-content.json)
// are inside base_output_dir and are therefore already ignored by each scanPath() call.
```

**Step 2: Commit**

```bash
git add src/cli/commands/runner.zig
git commit -m "docs: note combined outputs are already ignored via base_output_dir"
```

---

### Task 11: Final verification

**Step 1: Run full test suite**

```bash
zig test --dep options -Mroot=src/root.zig -Moptions=src/cli/options_fallback.zig 2>&1 | tail -30
```

Expected: all tests pass, no failures.

**Step 2: Full release build**

```bash
zig build -Doptimize=ReleaseFast 2>&1
```

Expected: builds successfully with no errors.

**Step 3: End-to-end smoke test**

```bash
# Multi-path: combined report should be generated
zig build run -- --path src --path src/cli --html 2>&1

# Single-path: no combined report
zig build run -- --path src --html 2>&1

# No --html: no combined report
zig build run -- --path src --path src/cli 2>&1
```

**Step 4: Final commit**

```bash
git add -u
git commit -m "feat: complete combined multi-path HTML report implementation"
```
