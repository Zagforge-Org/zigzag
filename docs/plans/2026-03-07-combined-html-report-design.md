# Combined Multi-Path HTML Report — Design

**Date:** 2026-03-07
**Status:** Approved, ready for implementation

## Problem

When multiple paths are defined in `zig.conf.json`, ZigZag generates one `report.html` per path (in per-path subdirectories of `zigzag-reports/`). There is no unified view. `zigzag run` shows results from individual paths separately, with no way to see aggregate stats or navigate across paths in a single dashboard.

## Goal

Generate a single combined `zigzag-reports/report.html` that aggregates all per-path results into a grouped, navigable dashboard — with global summary at the top and per-path sections below. Source file viewing must work in the combined report.

## Scope

**In scope (MVP):**
- Combined HTML report generated at `zigzag-reports/report.html`
- Combined content sidecar at `zigzag-reports/report-content.json`
- Global summary cards (total paths, files, lines, size)
- Per-path collapsible sections (first path expanded, rest collapsed)
- Per-path summary stats and language list
- Per-path file table with cross-path search
- Source viewer (same slide-in panel, loads from combined content sidecar)

**Out of scope (MVP):**
- Watch mode combined report updates (see Watch Mode section)
- Per-path charts
- Cross-path comparison views

## Architecture

### Backend (Zig)

#### New `ScanResult` struct (`runner.zig`)

Holds owned file and binary entry maps for one scanned path. Memory lifecycle is controlled entirely by `exec()`.

```zig
const ScanResult = struct {
    root_path: []const u8,           // not owned — points into cfg.paths
    file_entries: std.StringHashMap(JobEntry),
    binary_entries: std.StringHashMap(BinaryEntry),

    pub fn deinit(self: *ScanResult, allocator: std.mem.Allocator) void {
        // free all owned JobEntry and BinaryEntry fields
    }
};
```

#### `scanPath()` and `writePathReports()` split

`processPath()` is split into two phases:

- `scanPath(path, cfg, cache, pool, allocator, logger) → ScanResult` — walks the directory, runs jobs, returns owned maps. Writes nothing.
- `writePathReports(result, cfg, allocator, logger) void` — writes all per-path outputs (`.md`, `.json`, `.html`, `.llm.md`). Does **not** free `result`.

#### Updated `exec()` flow

```
var results: ArrayList(ScanResult) = .empty;
defer {
    for (results.items) |*r| r.deinit(allocator);
    results.deinit(allocator);
}

for each path:
    result = scanPath(...) catch |err| {
        log error, increment failed_paths, continue
    }
    writePathReports(result, ...)
    if cfg.html_output and paths.len > 1:
        results.append(allocator, result)
    else:
        result.deinit(allocator)

if cfg.html_output and results.items.len > 1:
    writeCombinedHtmlReport(results, cfg, allocator)
    writeCombinedContentJson(results, allocator)
```

`exec()` is the single owner of all memory. `writePathReports()` has no cleanup responsibility.

#### Output paths

Combined outputs are placed at the root of the output directory (not in a per-path subdir):

```
zigzag-reports/
  report.html             ← combined (new)
  report-content.json     ← combined content sidecar (new)
  src/
    report.html           ← per-path (unchanged)
    report-content.json   ← per-path (unchanged)
  tests/
    report.html
    report-content.json
```

Combined report is generated **only** when `cfg.html_output && cfg.paths.items.len > 1`.

#### Ignore list

`exec()` adds `zigzag-reports/report.html` and `zigzag-reports/report-content.json` to each path's ignore list before scanning. In practice, the output dir is already ignored wholesale, so this is defensive correctness.

### Data Format

Combined report JSON (injected at `__ZIGZAG_DATA__`):

```json
{
  "meta": {
    "combined": true,
    "path_count": 3,
    "successful_paths": 2,
    "failed_paths": 1,
    "file_count": 184,
    "generated_at": "2026-03-07 14:22:00",
    "version": "1.2.0"
  },
  "summary": {
    "source_files": 184,
    "binary_files": 10,
    "total_lines": 50000,
    "total_size_bytes": 1200000
  },
  "paths": [
    {
      "root_path": "./src",
      "summary": {
        "source_files": 120,
        "binary_files": 5,
        "total_lines": 30000,
        "total_size_bytes": 800000,
        "languages": [
          {"name": "Zig", "files": 80, "lines": 25000, "size_bytes": 600000}
        ]
      },
      "files": [
        {
          "path": "src/main.zig",
          "root_path": "./src",
          "size": 4096,
          "lines": 120,
          "language": "Zig"
        }
      ],
      "binaries": [
        {"path": "src/icon.png", "size": 2048}
      ]
    }
  ]
}
```

Key decisions:
- `meta.combined: true` lets the frontend branch without checking `paths` existence
- `meta.successful_paths` / `meta.failed_paths` exposes partial-failure state for debugging
- `meta.file_count` avoids recalculation in the template
- Each file entry carries `root_path` for future cross-path flat views
- Per-path `summary.languages` duplicates no global data; each section is self-contained

### Content Sidecar

`zigzag-reports/report-content.json` is a flat map of all file sources, merged across all paths.

**Key format:** `"{root_path}:{relative_path}"` — e.g., `"./src:src/main.zig"`.

This prevents collisions when two paths contain files with the same relative path (e.g., `./backend/src/main.zig` and `./frontend/src/main.zig`). The viewer looks up `content[root_path + ":" + file.path]`.

### Template

A new combined template, separate from the existing single-path dashboard. No changes to the existing `dashboard.html` or its JS.

**File layout:**

```
src/templates/src/
  combined.html          ← new shell template
  combined.ts            ← new multi-path app logic (→ combined.js via tsc)
  dashboard.css          ← shared, unchanged
  highlight.worker.js    ← shared, unchanged
  ... existing files unchanged

src/templates/
  dashboard.html              ← existing, unchanged
  combined-dashboard.html     ← new bundled output (generated by bundle.py)
```

**`combined.html`** injects shared assets via the existing bundler markers:
- `<!-- @inject: dashboard.css -->` — shared styles
- `<!-- @inject-text: dist/highlight.worker.js as prism-src -->` — shared worker
- `<!-- @inject: dist/combined.js -->` — combined-specific logic

**`combined.ts`** handles:
- Render global summary cards
- Render N collapsible path sections (first expanded, rest collapsed)
- Per-path file table (virtual scroll for large sets)
- Cross-path search (filters filename, relative path, language across all sections)
- Source viewer (same slide-in panel; content lookup uses `root_path + ":" + path` key)

**Zig side:** `@embedFile("../../../../../templates/combined-dashboard.html")` in a new `writeCombinedHtmlReport()` function in `html.zig`, alongside the existing `writeHtmlReport()`.

**Build:** `bundle.py` is extended to also process `combined.html → combined-dashboard.html`. `zig build bundle` produces both outputs deterministically.

## Watch Mode

In watch mode, per-path reports continue to update normally. **The combined report is not regenerated during watch mode.** It may become stale until the next full `zigzag run`. This is a documented scope boundary; combined watch support is a separate future feature.

## Error Handling

If `scanPath()` fails for a path (e.g., directory not found), `exec()` logs the error, increments `failed_paths`, and skips that path. The combined report is written with whatever paths succeeded. If zero paths succeed, no combined report is written.

The `meta.failed_paths` count in the combined JSON exposes this state for debugging without requiring UI changes in the MVP.

## Testing

New unit tests:

1. **`writeCombinedContentJson()`** — verify `root_path:rel_path` key format; verify content values are correct; verify no collision between paths with identical relative paths.
2. **`writeCombinedHtmlReport()`** — verify `__ZIGZAG_DATA__` marker is replaced; verify emitted JSON contains `"combined":true` and correct `path_count`.
3. **Generation condition** — combined report written when 2+ paths; not written when 1 path; not written when `html_output` is false.

No new runtime-only tests needed — the scanning logic is unchanged; the combined report is a thin composition layer over existing `ReportData`.
