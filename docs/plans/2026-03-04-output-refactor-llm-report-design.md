# Design: Output Refactor + LLM Report (v0.13.0)

**Date:** 2026-03-04
**Scope:** Approach A — Output location refactor + LLM-optimized report generation
**Deferred:** Intelligent splitting (pending real-world usage data)

---

## Problem Statement

The current output model places `report.md` inside the scanned source directory. This violates the tool's identity as an observational, analytical system external to the source tree. Derived artifacts (reports) should not live alongside source inputs.

Additionally, there is no artifact optimized for LLM ingestion. The full `report.md` contains verbosity, boilerplate, and large code blocks that consume context window unnecessarily.

---

## Guiding Principles

- **Output is derived, not source.** Reports belong outside the scanned tree.
- **Static condensing is the baseline.** LLM summarization requires no API dependency.
- **Progressive enhancement.** Phase 2 (LLM API) slots into the pipeline without redesign.
- **Splitting is deferred.** Design uncertainty around split heuristics warrants real-world usage before committing to behavior.

---

## Section 1: Output Location Refactor

### New Default Structure

```
<cwd>/
├── src/                            ← scanned source (untouched)
└── zigzag-reports/
    └── src/                        ← mirrors scanned relative path hierarchy
        ├── report.md
        ├── report.json             (if --json)
        ├── report.html             (if --html)
        └── report.llm.md           (if --llm-report)
```

All output paths are created if they do not exist (`makePath`).

### Path Resolution Rules

| Input | Output dir |
|-------|-----------|
| `./src` | `zigzag-reports/src/` |
| `./src/cli` | `zigzag-reports/src/cli/` |
| `/home/user/project/src` | `zigzag-reports/src/` (basename only for absolute paths) |
| Multiple paths with same basename | `zigzag-reports/src/` and `zigzag-reports/src_2/` (disambiguated with numeric suffix) |

- All output dirs are resolved relative to `cwd` unless `--output-dir` is an absolute path.
- `--output-dir <dir>` overrides the `zigzag-reports` base.
- `--output <filename>` renames the file within the resolved output dir (unchanged semantics).
- `--output-dir .` restores legacy behavior (output alongside source).

### Ignore List

`zigzag-reports/` is auto-added to the ignore list when scanning `.` (project root), preventing recursive report ingestion. If `--output-dir` points outside the project root, no auto-ignore is needed.

### Backward Compatibility

This is a **breaking change** — output location moves from inside the scanned path to `zigzag-reports/`. Version bumped to `0.13.0`. Users who require the old behavior can use `--output-dir .`.

### Config Wiring

**`FileConf`** adds:
```zig
output_dir: ?[]const u8,
```

**`Config`** adds:
```zig
output_dir: ?[]u8,
_output_dir_allocated: bool,
_output_dir_set_by_cli: bool,  // CLI wins over file conf
```

**`handlers.zig`**: new `handleOutputDir(cfg, allocator, value)`.
**`options.zig`**: new entry `--output-dir`.
**`runner.processPath()`**: resolves full output path, calls `std.fs.cwd().makePath()` with proper error handling for pre-existing dirs and permission failures.

---

## Section 2: LLM Report Generation

### Trigger

`--llm-report` CLI flag or `"llm_report": true` in `zig.conf.json`.
Output: `report.llm.md` in the same directory as `report.md`.

### Static Condensing Pipeline (Phase 1 — always on)

| Transform | Rule |
|-----------|------|
| **Boilerplate skip** | Files matching `*.lock`, `package-lock.json`, `go.sum`, `*.min.js`, `*.pb.go`, `*.generated.*` omitted entirely |
| **Binary skip** | Already excluded by existing pipeline — no change |
| **Blank line collapse** | Consecutive blank lines reduced to max 1 |
| **Comment stripping** | Single-line comments removed by extension: `//` (Zig/JS/Rust/Go/C), `#` (Python/Shell/Ruby), `--` (SQL/Lua), `%` (TeX). Multi-line comment stripping deferred to v2 (requires AST or careful heuristics). |
| **File truncation** | Files over `llm_max_lines` (default: 150) show first 60 + last 20 lines. Omission marker: `// [N lines omitted]` where N = original − 80. Proper code fences maintained around truncated sections. |

Statistics are calculated **after** boilerplate/binary files are excluded from "original" count, so the reduction % reflects only condensed source files.

### Report Structure

```markdown
# LLM Context: src/
> This report is condensed for LLM ingestion. The full human-readable report is available at report.md.
> ZigZag v0.13.0 · 2026-03-04

## Project Description
<!-- Included only when `llm_description` is set in zig.conf.json -->
ZigZag is a CLI tool that recursively scans directories and generates markdown reports...

## Statistics
- Source files: 42  |  Binary files: 3  |  Boilerplate skipped: 5
- Languages: Zig (38), Python (4)
- Original lines: 8,420  →  Condensed: ~1,200  (86% reduction)

## File Index
- src/main.zig (38 lines, full)
- src/cli/handlers.zig (condensed — 80 of 890 lines shown)
- src/cli/commands/config.zig (condensed — 80 of 312 lines shown)

## Source

### src/main.zig
```zig
<full content>
```

### src/cli/handlers.zig *(condensed — 80 of 890 lines shown)*
```zig
<first 60 lines>
// [810 lines omitted]
<last 20 lines>
```
```

### Phase 2: LLM API Summarization (Deferred)

The pipeline is designed so a future `--llm-optimize` flag inserts a semantic summarization step **after** Phase 1 static reduction. The LLM receives already-condensed content, bounding token cost. Input contract: condensed Markdown string per file. Output: replacement Markdown string. Failure falls back to static condensed content.

---

## Section 3: Configuration & CLI

### New CLI Flags

```
--output-dir <dir>    Base directory for all report output (default: zigzag-reports)
--llm-report          Generate an LLM-optimized condensed report alongside report.md
```

### New `zig.conf.json` Fields

```json
{
  "output_dir": "zigzag-reports",
  "llm_report": true,
  "llm_max_lines": 150,
  "llm_description": "Brief description of the project for LLM context preamble."
}
```

`handleInit` updates `defaultContent()` to include the new fields (commented out with defaults shown), so new users see the options.

### Config Priority (lowest → highest)

1. `initDefault()` → `output_dir = "zigzag-reports"`, `llm_report = false`, `llm_max_lines = 150`, `llm_description = null`
2. `zig.conf.json` → `applyFileConf()` applies any set fields
3. CLI arguments → always win; `_output_dir_set_by_cli` prevents file conf from overriding

**Rule:** CLI arguments override all file-based or default configuration values.

### New Config Fields

**`FileConf`** additions:
```zig
output_dir: ?[]const u8,
llm_report: ?bool,
llm_max_lines: ?u64,
llm_description: ?[]const u8,
```

**`Config`** additions:
```zig
output_dir: ?[]u8,
_output_dir_allocated: bool,
_output_dir_set_by_cli: bool,
llm_report: bool,
llm_max_lines: u64,
llm_description: ?[]u8,
_llm_description_allocated: bool,
```

---

## Section 4: Testing Strategy

### Unit Tests (inline, per-file pattern)

| File | Tests |
|------|-------|
| `handlers.zig` | `handleOutputDir`: sets field, trims whitespace, frees previous allocation; `handleLlmReport`: sets flag |
| `config.zig` | `applyFileConf` applies `output_dir`, `llm_report`, `llm_max_lines`, `llm_description`; CLI `_output_dir_set_by_cli` prevents override; `initDefault` sets correct defaults |
| `report.zig` | `writeLlmReport`: boilerplate file omitted, truncation marker matches exact omitted count, blank-line collapse, comment stripping per extension, code fence continuity across truncation boundary, `llm_description` appears when set and absent when null |
| `runner.zig` | Output path resolves correctly for relative paths; absolute paths use basename only; `--output-dir .` produces path inside scanned dir; collision disambiguation appends numeric suffix |

### Integration Test

Scan a temp dir containing:
- One small file (< 150 lines) — expect full inclusion
- One large file (> 150 lines, with single-line comments) — expect truncation with correct `// [N lines omitted]` count and stripped comments
- One lock file (`package-lock.json`) — expect complete omission

Verify:
- `report.llm.md` exists in `zigzag-reports/<tempdir>/`
- Lock file absent from LLM report
- Large file truncated; omission count = original − 80
- Statistics line shows correct original vs condensed line counts and reduction %
- `llm_description` appears in report when set in config

### Regression Tests

All existing `--json`, `--html`, `--watch` tests updated to resolve output paths under `zigzag-reports/<path>/report.*`. Smoke test for `--output-dir .` confirms legacy path behavior still works.

### Version Bump

`build.zig.zon` and `config.zig::VERSION`: `0.12.x → 0.13.0`

---

## What Is Explicitly Deferred

| Feature | Reason |
|---------|--------|
| Intelligent splitting (`part-001.md`) | Design uncertainty: optimal split heuristics, threshold defaults, LLM-report coordination with parts — all require real-world usage data |
| Multi-line comment stripping | Requires AST or complex heuristics; risk of corrupting content outweighs v1 benefit |
| LLM API summarization (`--llm-optimize`) | API dependency, latency, cost — explicitly a Phase 2 enhancement |

Splitting is intentionally deferred, not missing. The output directory structure (`zigzag-reports/<path>/`) already accommodates `part-001.md`, `part-002.md` without redesign.
