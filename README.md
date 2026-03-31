# ZigZag

<img src="src/assets/logo.png" alt="zig-zag logo" width="64" height="64">

A blazing-fast code analytics tool that converts source code into comprehensive Markdown reports, optimized for modern developer workflows and LLM-powered tooling.

## Overview

**ZigZag** recursively scans directories provided through CLI flags or a `zig.conf.json` configuration file and produces **Markdown**, **HTML**, and **JSON** reports containing your full source code, designed for modern workflows and tooling. Each **Markdown** report includes syntax-aware code blocks. The `--llm-report` flag produces a condensed, token-efficient report for LLM ingestion, with optional chunking for large codebases. The most recommended workflow is running `zigzag init` to initialize a `zig.conf.json` file with predefined defaults. ZigZag automatically ignores binary files to ensure outputs remain text-based and human-readable.

## Features

- **Optimized file reading** designed for high-performance processing
- **Intelligent binary file detection** prevents corrupted output and preserves human-readable format
- **Flexible ignore patterns** supports wildcards, extensions, and exact matches
- **Persistent caching system** with validation and atomic updates
- **Parallel processing** distributes tasks across worker pools for concurrent execution
- **Cross-platform compatibility**: `Windows`, `Linux`, and `macOS`
- **Timezone-aware timestamps** with configurable offsets
- **Multi-path support** for processing multiple directories simultaneously
- **Automatic directory skipping** — `node_modules`, `.git`, `.turbo`, `.nx`, `.parcel-cache`, and more
- **JSON configuration** (`zig.conf.json`) for project-level defaults
- **Real-time watch mode** regenerates reports on file changes across MD, JSON, and HTML outputs
- **HTML Dashboard** (`--html`) — interactive single-file dashboard with charts, virtual-scroll source viewer, and syntax highlighting; live-reloads in watch mode
- **LLM report** (`--llm-report`) — condensed, token-efficient report with per-file condensation; supports chunking via `--chunk-size` for large codebases
- **Phase progress** — scan / aggregate / write phase indicators on stderr with a final rich summary (machine info, timings, file counts)
- **Bench subcommand** — per-phase timing table with CPU model and core count
- **Upload to ZagForge** (`--upload`) — pushes the scan result to ZagForge; runs once on initial scan in watch mode

## Installation

### Homebrew (macOS / Linux) — recommended

```bash
brew tap LegationPro/zigzag
brew install zigzag
```

### Pre-built binaries

Download the latest archive for your platform from the [Releases page](https://github.com/LegationPro/zigzag/releases), extract it, and place the `zigzag` binary somewhere on your `PATH`.

**macOS — Gatekeeper notice**

Because the binary is downloaded from the internet, macOS will quarantine it on first run. After extracting, remove the flag with:

```bash
xattr -d com.apple.quarantine zigzag
```

Or right-click the binary in Finder → **Open** → **Open** to approve it once.

> The release binaries are ad-hoc code-signed, which avoids the "damaged and can't be opened" error on Apple Silicon. Full notarization requires an Apple Developer account; the Homebrew tap is the easiest path for a warning-free install.

### Prerequisites (building from source)

- Zig 0.15.2

### Building from Source

```bash
git clone https://github.com/LegationPro/zigzag.git
cd zigzag
```

**With `make` (Linux/macOS):**

```bash
make init   # init submodules (sparse checkout)
make build  # build release binary
```

**Without `make` (cross-platform):**

```bash
python scripts/setup.py        # init + build
python scripts/setup.py all    # init + build + test
```

The executable will be available at `zig-out/bin/zigzag`.

## Quick Start

### Initialize a project

```bash
# Create zig.conf.json with default values in the current directory
zigzag init
```

**Generated `zig.conf.json`:**

```json
{
  "paths": [],
  "ignores": [],
  "skip_cache": false,
  "small_threshold": 1048576,
  "mmap_threshold": 16777216,
  "timezone": null,
  "output": "report.md",
  "watch": false,
  "log": false,
  "json_output": false,
  "html_output": false,
  "output_dir": "zigzag-reports",
  "llm_report": false,
  "llm_max_lines": 150,
  "llm_description": null,
  "llm_chunk_size": null,
  "upload": false
}
```

### Run from config file

```bash
# Run using paths and options from zig.conf.json
zigzag run

# Run from config file, overriding specific options via CLI flags
zigzag run --paths ./src --ignores "*.test.zig"
zigzag run --watch
```

### Example zig.conf.json

```json
{
  "paths": ["docs", "src"],
  "ignores": [".secret", ".env"],
  "skip_cache": false,
  "small_threshold": 1048576,
  "mmap_threshold": 16777216,
  "timezone": null,
  "output": "report.md",
  "watch": true,
  "log": false,
  "json_output": true,
  "html_output": true,
  "output_dir": "zigzag-reports",
  "llm_report": true,
  "llm_max_lines": 150,
  "llm_description": null,
  "llm_chunk_size": "500k",
  "upload": false
}
```

## Subcommands

| Command | Description |
|---------|-------------|
| `init`  | Creates `zig.conf.json` with default values in the current directory. Warns and skips if the file already exists and is non-empty; overwrites silently if the file exists but is empty. |
| `run`   | Loads `zig.conf.json` as the base config, then applies any CLI flags on top. Useful for project-level defaults. |
| `bench` | Runs the full report pipeline and prints a per-phase timing table (scan, aggregate, write) with CPU model and core count to stderr. |

Without a subcommand, ZigZag applies CLI flags directly (no file config is loaded).

## CLI Flags

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--version` | `bool` | `false` | Show ZigZag version. |
| `--help` | `bool` | `false` | Show help information. |
| `--skip-cache` | `bool` | `false` | Skip cache operations and clear the cache. |
| `--small` | `number` | `1048576` | Threshold for small files in bytes. |
| `--mmap` | `number` | `16777216` | Threshold for memory-mapped files in bytes. |
| `--paths` | `string` | — | Directory to scan. Comma-separated or repeated for multiple paths. |
| `--ignores` | `string[]` | `[]` | Pattern(s) to ignore. Comma-separated or repeated for multiple patterns. |
| `--timezone` | `string` | `null` | Timezone offset (e.g. `"+1"`, `"-5:30"`). |
| `--watch` | `bool` | `false` | Enable watch mode to regenerate reports on file changes. |
| `--no-watch` | `bool` | `false` | Disable watch mode, overriding `"watch": true` in `zig.conf.json`. |
| `--output` | `string` | `"report.md"` | Output filename for the Markdown report. |
| `--output-dir` | `string` | `"zigzag-reports"` | Directory to store generated reports. |
| `--json` | `bool` | `false` | Generate a JSON report alongside Markdown. |
| `--html` | `bool` | `false` | Generate an interactive HTML dashboard alongside Markdown. |
| `--llm-report` | `bool` | `false` | Generate a condensed LLM-optimised report. |
| `--chunk-size` | `string` | — | Split the LLM report into chunks of this size (e.g. `500k`, `2m`). Omit or set to `null` in config for a single file. |
| `--log` | `bool` | `false` | Enable logging. |
| `--open` | `bool` | `false` | Automatically open the HTML report in a browser. |
| `--upload` | `bool` | `false` | Upload the scan result to ZagForge. Requires `ZAGFORGE_API_KEY` env var or `~/.zagforge/credentials`. Only effective with the `run` subcommand or in watch mode (uploads once on initial scan). |

## Config Loading Priority

Settings are applied from lowest to highest priority (later values win):

1. Hard-coded defaults
2. `zig.conf.json` (when using `zigzag run`)
3. CLI flags (always override file config)

When the first `--paths` CLI flag is encountered, all file-loaded paths are replaced. Same for `--ignores`. Scalar fields (skip_cache, watch, etc.) always take the last CLI value. `--no-watch` is a permanent override: it forces `watch = false` regardless of the config file.

## Config Fields

All fields supported in `zig.conf.json`:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `paths` | `string[]` | `[]` | Directories to scan |
| `ignores` | `string[]` | `[]` | Patterns to exclude from scanning |
| `skip_cache` | `bool` | `false` | Bypass the cache and rebuild from scratch |
| `small_threshold` | `number` | `1048576` | File size limit (bytes) for full in-memory reads |
| `mmap_threshold` | `number` | `16777216` | File size limit (bytes) for memory-mapped I/O |
| `timezone` | `string\|null` | `null` | Timezone offset for report timestamps |
| `output` | `string` | `"report.md"` | Output filename for Markdown reports |
| `watch` | `bool` | `false` | Enable filesystem watch mode |
| `log` | `bool` | `false` | Enable logging output |
| `json_output` | `bool` | `false` | Generate JSON reports |
| `html_output` | `bool` | `false` | Generate HTML dashboards |
| `output_dir` | `string` | `"zigzag-reports"` | Output directory for all reports |
| `llm_report` | `bool` | `false` | Enable LLM-optimized reporting |
| `llm_max_lines` | `number` | `150` | Max lines per file in LLM reports |
| `llm_description` | `string\|null` | `null` | Project description for LLM reports |
| `llm_chunk_size` | `number\|string\|null` | `null` | Split LLM report into chunks of this size. `null` or `0` = single file. Accepts numeric bytes or string with `k`/`m` suffixes (e.g. `500000` or `"500k"`) |
| `upload` | `bool` | `false` | Upload scan result to ZagForge. Requires `ZAGFORGE_API_KEY` env var or `~/.zagforge/credentials` |

## LLM Report

Pass `--llm-report` (or set `"llm_report": true` in `zig.conf.json`) to generate a condensed report alongside the Markdown file. The LLM report is written as `report.llm.md` in the same directory.

Each source file is condensed: files exceeding `llm_max_lines` are truncated to the first 60 and last 20 lines with an omission notice. Boilerplate files (`package-lock.json`, `yarn.lock`, `*.lock`, etc.) are excluded automatically.

### LLM Chunking

For large codebases, pass `--chunk-size` to split the output across multiple files. Accepts byte counts with optional `k`/`m` suffixes (case-insensitive):

```bash
zigzag run --paths ./src --llm-report --chunk-size 500k
zigzag run --paths ./src --llm-report --chunk-size 2m
```

The same format works in `zig.conf.json` — use a quoted string:

```json
"llm_chunk_size": "500k"
```

Plain numbers are also accepted for backward compatibility (`"llm_chunk_size": 500000`). Set to `null` (or omit) to disable chunking.

When chunking is active:
- Chunk 1 is written to `report.llm.md`
- Additional chunks are written to `report.llm-2.md`, `report.llm-3.md`, …
- A `report.llm.manifest.json` is created listing all chunk files
- Each continuation chunk starts with a `# Project: … (continued — chunk N)` header

Files are never split across chunk boundaries.

## Ignore Patterns

ZigZag supports multiple ignore pattern types:

### Pattern Types

| Pattern Type | Example | Description |
|-------------|---------|-------------|
| **Wildcard Extension** | `*.png`, `*.svg` | Ignores all files with the specified extension |
| **Exact Filename** | `test.txt`, `config.json` | Ignores files with an exact name match |
| **Wildcard Prefix** | `test*` | Ignores files starting with the prefix |
| **Wildcard Suffix** | `*config` | Ignores files ending with the suffix |
| **Directory Name** | `node_modules`, `.cache` | Ignores directories and all their contents |

### Auto-Ignored Directories

ZigZag automatically skips common directories:

- `node_modules`, `.bin`
- `.git`, `.svn`, `.hg`
- `.cache`, `.zig-cache`
- `__pycache__`, `.pytest_cache`
- `target`, `build`, `dist`
- `.idea`, `.vscode`
- `.turbo`, `.nx`, `.parcel-cache`
- `zig.conf.json`

### Binary File Detection

Binary files are automatically detected and excluded:

1. **Extension-based** (fast path):
   - Images: `.png`, `.jpg`, `.jpeg`, `.gif`, `.bmp`, `.ico`, `.webp`
   - Archives: `.zip`, `.tar`, `.gz`, `.7z`, `.rar`, `.bz2`, `.zst`, `.lz4`, `.xz`, `.lzma`, `.zstd`
   - Executables: `.exe`, `.dll`, `.so`, `.dylib`
   - Media: `.mp3`, `.mp4`, `.avi`, `.mov`, `.mkv`
   - Fonts: `.woff`, `.woff2`, `.ttf`, `.otf`, `.eot`
   - Compiled: `.class`, `.jar`, `.pyc`, `.o`, `.a`
   - Documents: `.pdf`
   - Databases: `.db`, `.sqlite`

2. **Content-based** (fallback): checks for null bytes and non-printable character ratio in the first 512 bytes.

## Output Format

Each processed directory contains a `report.md` file with the following structure:

````md
# Code Report for: `./src`

Generated on: 2026-01-30 14:23:45 (UTC+1)

---

## Table of Contents

- [./src/main.zig](#./src/main.zig)
- [./src/utils.zig](#./src/utils.zig)
...

---

## File: `./src/main.zig`

**Metadata:**
- **Size:** 2.28 KB
- **Language:** zig
- **Last Modified:** 2026-01-23 10:38:54 (UTC+1)

```zig
const std = @import("std");
// ... file content
```

...
````

## Watch Mode

Watch mode uses OS-level filesystem events (inotify on Linux, kqueue on macOS/BSD, `ReadDirectoryChangesW` on Windows) to detect changes instantly. Only the changed file is re-read from disk; the report is rebuilt from the in-memory state of all other files.

Events are debounced: rapid changes within a 50 ms window are batched into a single report write.

In HTML mode, a lightweight `.stamp` sidecar file is written alongside the HTML report. The browser polls the stamp file instead of the full HTML, then fetches the HTML only when the stamp changes.

When `--upload` is also active, ZigZag uploads the initial snapshot once after the first scan and does not re-upload on subsequent changes.

Use `--no-watch` to override `"watch": true` set in `zig.conf.json` and run a single-shot report instead:

```bash
zigzag run --no-watch
```

Press `Ctrl+C` to stop.

## Upload

Pass `--upload` (or set `"upload": true` in `zig.conf.json`) to push the scan result to [ZagForge](https://zagforge.com) after the report is written.

```bash
zigzag run --upload
```

### Authentication

The API key is discovered in this order:

1. `ZAGFORGE_API_KEY` environment variable
2. `~/.zagforge/credentials` file containing a `ZAGFORGE_API_KEY=zf_pk_…` line

### Watch mode behaviour

When `--upload` is active in watch mode, ZigZag uploads the initial snapshot once after the first scan completes. It does **not** re-upload on subsequent file changes — use `zigzag run --upload` for one-shot uploads.

### Timeout

Upload requests time out after **30 seconds**. If the request fails, an error is printed to stderr and the watch loop continues.

### Using `--upload` without `run`

Passing `--upload` without the `run` subcommand (i.e. in flag-only mode) has no effect. ZigZag will print a warning:

```
warning: --upload has no effect without the 'run' subcommand
warning: Usage: zigzag run --upload
```

## JSON Output

Pass `--json` (or set `"json_output": true`) to generate a machine-readable JSON report alongside the Markdown file. The JSON file uses `.json` replacing `.md` (e.g. `report.json`).

### JSON Report Structure

```json
{
  "meta": {
    "version": "0.16.0",
    "generated_at_ns": 1738245534000000000,
    "scanned_paths": ["./src"]
  },
  "summary": {
    "source_files": 12,
    "binary_files": 3,
    "total_lines": 1450,
    "total_size_bytes": 58320,
    "languages": [
      { "name": "zig", "files": 10, "lines": 1300, "size_bytes": 52000 }
    ]
  },
  "files": [
    {
      "path": "./src/main.zig",
      "size": 2345,
      "mtime_ns": 1738245534000000000,
      "extension": ".zig",
      "language": "zig",
      "lines": 87
    }
  ],
  "binaries": [
    {
      "path": "./src/assets/logo.png",
      "size": 4096,
      "mtime_ns": 1738240000000000000,
      "extension": ".png"
    }
  ]
}
```

## HTML Dashboard

Pass `--html` (or set `"html_output": true`) to generate a self-contained interactive HTML report. The HTML file is written next to the Markdown with `.html` replacing `.md`.

The dashboard is a **single `.html` file** — all CSS, JavaScript, and syntax highlighting are bundled. Open it directly in any browser; no server required.

### Dashboard Features

| Feature | Description |
|---------|-------------|
| **Summary cards** | Total files, lines, size, and languages at a glance |
| **Language chart** | Bar chart of file counts per language |
| **Size distribution** | Histogram of file sizes across the codebase |
| **File table** | Sortable, searchable table with path, language, size, and line count |
| **Source viewer** | Click any file to open a slide-in panel showing its source code |
| **Syntax highlighting** | Off-thread Prism highlighting for 20+ languages |
| **Virtual scroll** | Files over 500 lines or 200 KB use virtual scrolling — only visible lines are rendered |
| **Dark mode** | Follows the OS `prefers-color-scheme` setting automatically |
| **Watch live-reload** | Polls a `.stamp` sidecar file; reloads the report without a full page refresh |

### Supported Languages

Zig, JavaScript, TypeScript, Lua, JSON, HTML/XML/SVG, CSS, SCSS, Bash/Shell, C, C++, Rust, Go, Python, Ruby, Java, Markdown, TOML, YAML, SQL.

## Cache System

ZigZag includes a smart caching system that:

- Persists between runs in `.cache/files/`
- Validates on startup to remove stale entries
- Uses file metadata (mtime, size) for change detection
- Performs atomic updates to prevent corruption

Cache location: `./.cache/` (relative to working directory)

## Performance

### File Reading Strategies

Files are read fully into memory using `readFileAlloc`. The `--small` and `--mmap` thresholds configure the `readFileAuto` utility (which supports mmap and chunked streaming for large files), but the main processing path loads each file directly into memory regardless of size.

### Performance Tips

1. **Use cache**: Don't use `--skip-cache` unless necessary
2. **Tune thresholds**: Adjust `--small` and `--mmap` based on your file sizes
3. **Parallel processing**: More threads for large projects (auto-detected from CPU cores)
4. **Ignore patterns**: Use specific patterns to exclude unnecessary files early

## Testing

```bash
# Run all tests (via Makefile — avoids WSL2 output-buffering hang)
make test

# Direct invocation
zig test --dep options -Mroot=src/root.zig -Moptions=src/cli/version/fallback.zig
```

> **Note:** `zig build test` may hang indefinitely on WSL2 due to output buffering. Use `make test` instead.


## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing`)
5. Open a Pull Request

### Development Setup

```bash
git clone https://github.com/LegationPro/zigzag.git
cd zigzag

# Init submodules + build (make)
make init && make build

# Init submodules + build (cross-platform, no make required)
python scripts/setup.py

# Run tests (make)
make test

# Run tests (cross-platform)
python scripts/setup.py test

# Format code
zig fmt src/
```

### Code Style

- Follow Zig's standard formatting (`zig fmt`)
- Write tests for new features in `*_test.zig` files alongside their modules
- No inline tests in main modules under `report/` and `config/` — use `_test.zig` files
- Register new test files in `src/root.zig`

## License

MIT License — see `LICENSE.md` for details.

## Links

- [ZagForge](https://zagforge.com) — official product page
- [Documentation](https://docs.zagforge.com)
- [GitHub Repository](https://github.com/LegationPro/zigzag)
- [Issue Tracker](https://github.com/LegationPro/zigzag/issues)
- [Zig Language](https://ziglang.org/)

---

**Made with ❤️ using Zig**
