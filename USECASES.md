# ZigZag — Use Cases

ZigZag scans a directory tree and produces a single Markdown file containing every source file's content, metadata, and a table of contents. This page covers practical scenarios from first-time setup to advanced automation.

---

## Table of Contents

- [Getting Started](#getting-started)
- [Basic Scanning](#basic-scanning)
- [Config File Workflow](#config-file-workflow)
- [Filtering Files](#filtering-files)
- [Multiple Paths](#multiple-paths)
- [Watch Mode](#watch-mode)
- [Custom Output](#custom-output)
- [Timezone-Aware Reports](#timezone-aware-reports)
- [Performance Tuning](#performance-tuning)
- [CI / Automation](#ci--automation)
- [Combining Flags](#combining-flags)

---

## Getting Started

### Initialize a project

Run this once inside any project directory. It creates `zig.conf.json` pre-filled with all available options and their defaults.

```bash
zigzag init
```

Generated `zig.conf.json`:

```json
{
  "paths": [],
  "ignore_patterns": [],
  "skip_cache": false,
  "skip_git": false,
  "small_threshold": 1048576,
  "mmap_threshold": 16777216,
  "timezone": null,
  "output": "report.md",
  "watch": false
}
```

Edit this file to set your permanent defaults. Any key can be left out — omitted keys fall back to the built-in default shown above.

---

## Basic Scanning

### Scan a single directory

```bash
zigzag --path ./src
```

Produces `src/report.md` containing every text/source file found under `./src`, sorted alphabetically, with a table of contents and per-file metadata (size, language, last modified).

### Scan from a config file

After editing `zig.conf.json` to include your paths:

```json
{
  "paths": ["./src"]
}
```

Just run:

```bash
zigzag run
```

No flags required. ZigZag reads the config file and proceeds.

---

## Config File Workflow

`zig.conf.json` acts as your persistent defaults. CLI flags **override** the config file for the duration of that run — the file itself is never modified.

### Override rule

| Source | Priority |
|--------|----------|
| Built-in defaults | Lowest |
| `zig.conf.json` | Middle |
| CLI flags | Highest |

For list fields (`paths`, `ignore_patterns`), the **first** CLI flag for that field replaces the entire list from the config file. Subsequent CLI flags for the same field accumulate.

### Example: permanent ignore list + ad-hoc override

`zig.conf.json`:
```json
{
  "paths": ["./src"],
  "ignore_patterns": ["*.test.ts", "*.spec.ts"]
}
```

Normal run — uses the config file patterns:
```bash
zigzag run
```

One-off run ignoring an extra directory, overriding the file patterns entirely:
```bash
zigzag run --ignore "*.test.ts" --ignore "*.spec.ts" --ignore "fixtures"
```

---

## Filtering Files

### Ignore by extension

```bash
zigzag --path ./src --ignore "*.png" --ignore "*.svg"
```

### Ignore a specific file

```bash
zigzag --path . --ignore "secrets.env"
```

### Ignore a directory

```bash
zigzag --path . --ignore "vendor" --ignore "generated"
```

### Wildcard prefix / suffix

```bash
# All files starting with "temp_"
zigzag --path ./src --ignore "temp_*"

# All files ending with ".bak"
zigzag --path ./src --ignore "*.bak"
```

### Auto-ignored (no configuration needed)

ZigZag always skips:

- Binary files — images, executables, archives, fonts, compiled objects, etc.
- `node_modules`, `.git`, `.svn`, `.hg`
- `__pycache__`, `.pytest_cache`
- `target`, `build`, `dist`
- `.idea`, `.vscode`, `.DS_Store`
- The `.cache` directory used by ZigZag itself
- The output report file (e.g., `report.md`) to avoid self-inclusion

---

## Multiple Paths

Generate a separate report for each path. Each report is written into its own directory.

```bash
zigzag --path ./frontend/src --path ./backend/src --path ./shared
```

This creates:
- `./frontend/src/report.md`
- `./backend/src/report.md`
- `./shared/report.md`

In `zig.conf.json` for permanent multi-repo setups:

```json
{
  "paths": ["./frontend/src", "./backend/src", "./shared"]
}
```

Then just:

```bash
zigzag run
```

---

## Watch Mode

Watch mode uses OS-level filesystem events — inotify on Linux, kqueue on macOS/BSD, ReadDirectoryChangesW on Windows — to react instantly to changes. Only the file that changed is re-read from disk; the rest of the report is rebuilt from in-memory state. Events within a 50 ms window are batched together before the report is rewritten.

### Enable via flag

```bash
zigzag --path ./src --watch
```

### Enable via config file

```json
{
  "paths": ["./src"],
  "watch": true
}
```

```bash
zigzag run
```

### Override watch settings from the CLI

Config file enables watch by default, but you want a one-off run:

```bash
# --watch is not passed, so watch stays false (only a single run)
zigzag run --path ./src
```

> **Note:** Watching runs until you press `Ctrl+C`. The report is fully written before the watcher resumes listening.

---

## Custom Output

By default the report is written to `report.md` inside each scanned directory. Use `--output` to change the filename.

### Different filename

```bash
zigzag --path ./src --output context.md
```

Writes to `./src/context.md`.

### Per-project permanent setting

```json
{
  "paths": ["./src"],
  "output": "llm-context.md"
}
```

```bash
zigzag run
# writes ./src/llm-context.md
```

### Override the config file name from the CLI

```bash
zigzag run --output one-off.md
```

---

## Timezone-Aware Reports

The "Last Modified" timestamp in each file entry and the report header use UTC by default. Pass `--timezone` to show local time instead.

### Formats accepted

| Format | Meaning |
|--------|---------|
| `+1` | UTC+1 (e.g., CET) |
| `-5` | UTC-5 (e.g., EST) |
| `+5:30` | UTC+5:30 (e.g., IST) |
| `-3:30` | UTC-3:30 (e.g., NST) |

```bash
zigzag --path ./src --timezone +1
```

### Set permanently in config

```json
{
  "paths": ["./src"],
  "timezone": "+5:30"
}
```

---

## Performance Tuning

ZigZag uses a persistent file cache (`.cache/`) to avoid re-reading unchanged files. On large codebases, only modified files are processed on subsequent runs.

### Skip the cache (force full rescan)

```bash
zigzag --path ./src --skip-cache
```

This clears the cache directory and does a fresh read of every file. Useful after major refactors or if the cache becomes stale.

### Small file threshold

Files below this size are read directly without SHA-256 hashing for cache invalidation (size + mtime are enough). Default: 1 MiB.

```bash
# Set to 512 KiB
zigzag --path ./src --small 524288
```

In `zig.conf.json`:
```json
{
  "small_threshold": 524288
}
```

### mmap threshold

Files above this size are read using memory-mapped I/O instead of heap allocation. Default: 16 MiB. Tune this on systems with limited address space or for very large files.

```bash
zigzag --path ./src --mmap 33554432
```

---

## CI / Automation

### Generate a snapshot report in CI

```bash
zigzag --path ./src --skip-cache --output snapshot.md
```

`--skip-cache` ensures a clean run every time regardless of any leftover cache from a previous job.

### Check in the config, generate on demand

Commit a `zig.conf.json` with team-agreed settings:

```json
{
  "paths": ["./src", "./lib"],
  "ignore_patterns": ["*.test.ts", "*.spec.ts", "*.snap"],
  "output": "codebase.md",
  "timezone": "+0"
}
```

Every developer (and CI) just runs:

```bash
zigzag run
```

### Generate for multiple services from a monorepo

```bash
zigzag --path ./services/auth \
       --path ./services/payments \
       --path ./services/notifications \
       --ignore "*.generated.ts" \
       --output service-report.md
```

Each service directory gets its own `service-report.md`.

---

## Combining Flags

Flags compose freely. CLI values override the corresponding `zig.conf.json` fields for that run.

### Thorough one-off scan, skipping tests and assets

```bash
zigzag run \
  --ignore "*.test.*" \
  --ignore "*.spec.*" \
  --ignore "*.png" \
  --ignore "*.svg" \
  --ignore "fixtures" \
  --output full-review.md
```

### Live watch with custom output, skipping cache

```bash
zigzag --path ./src \
       --watch \
       --output live.md \
       --skip-cache
```

### Multi-path watch with timezone

```bash
zigzag --path ./frontend \
       --path ./backend \
       --watch \
       --timezone -5 \
       --output review.md
```
