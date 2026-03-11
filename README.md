# ZigZag

<img src="src/assets/logo.png" alt="zig-zag logo" width="64" height="64">

A blazing-fast code analytics tool that converts source code into comprehensive Markdown reports, optimized for modern developer workflows and LLM-powered tooling.

## Overview

**ZigZag** recursively scans directories provided through CLI `--flags` or a `zig.conf.json` configuration file and produces **Markdown**, **HTML**, and **JSON** reports containing your full source code, designed for modern workflows and tooling. Each **Markdown** report includes syntax-aware code blocks. The `--llm-report` flag can be enabled for LLM optimized code reports. The most recommended workflow is running `zigzag init` to initialize a `zig.conf.json` file with predefined defaults. ZigZag automatically ignores binary files to ensure outputs remain text-based and human-readable.

## Features

- **Optimized file reading** designed for high-performance processing
- **Intelligent binary file detection** prevents corrupted markdown output and preserves human-readable format
- **Flexible ignore patterns** supports wildcards, extensions, and exact matches
- **Persistent caching system** with validation and atomic updates
- **Parallel processing** distributes tasks across worker pools for concurrent execution
- **Cross-platform compatibility** includes large OS support: `Windows`, `Linux`, and `macOS`
- **Timezone-aware timestamps** with configurable offsets
- **Multi-path support** for processing multiple directories simultaneously
- **Automatic ignore for common directories** (node_modules, .git)
- **JSON configuration** (`zig.conf.json`) to make development easier and more manageable
- **Real-time watch mode** for real-time updates across MD, JSON and HTML files
- **HTML Dashboard** (`--html`) modern interactive statically generated HTML dashboard supplied with analytical data supported with real-time updates using watch mode. Supports multiple popular programming languages with virtual scrolling source viewer and syntax highlighting.

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

> The release binaries are ad-hoc code-signed, which avoids the "damaged and can't be opened" error on Apple Silicon. Full notarization (which would remove the prompt entirely) requires an Apple Developer account; the Homebrew tap is the easiest path for a warning-free install.

### Prerequisites (building from source)

- Zig version 0.15.2

### Building from Source

```bash
git clone https://github.com/LegationPro/zigzag.git
cd zigzag
zig build -Doptimize=ReleaseFast
```

The executable will be available at `zig-out/bin/zigzag`.

On Unix systems, running `zigzag.sh` automatically places the binary under `/usr/local/bin`.

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
  "ignore_patterns": [],
  "skip_cache": false,
  "skip_git": false,
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
  "llm_description": null
}
```

### Run from config file

```bash
# Run using paths and options from zig.conf.json
zigzag run

# Run from config file, overriding specific options via CLI flags
zigzag run --path ./src --ignore "*.test.zig"
zigzag run --watch
```

### Usage

```
{
    "paths": ["docs", "src"],          // directories that will have their own reports
    "ignore_patterns": [".secret", ".env"], // files, folders to be ignored during report generation
    "skip_cache": false,               // clears cache on each run
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
    "llm_description": null
}
```

## Subcommands

| Command | Description |
|---------|-------------|
| `init`  | Creates `zig.conf.json` with default values in the current directory. No-ops if the file already exists. |
| `run`   | Loads `zig.conf.json` as the base config, then applies any CLI flags on top. Useful for project-level defaults. |

Without a subcommand, ZigZag applies CLI flags directly (no file config is loaded).

## Config Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `--version` | `bool` | `false` | Show ZigZag version. |
| `--help` | `bool` | `false` | Show help information. |
| `--skip-cache` | `bool` | `false` | Skip cache operations and clear the cache. |
| `--small` | `number` | `N/A` | Threshold for small files in bytes. |
| `--mmap` | `number` | `N/A` | Threshold for memory-mapped files in bytes. |
| `--path` | `string` | `N/A` | Directory to scan (can be specified multiple times). |
| `--ignore` | `string[]` | `[]` | Pattern(s) to ignore (same syntax as `zig.conf.json`). |
| `--timezone` | `string` | `null` | Timezone offset (e.g., `"+1"`, `"-5:30"`). |
| `--watch` | `bool` | `false` | Enable watch mode to regenerate reports on file changes. |
| `--output` | `string` | `"report.md"` | Output filename for the Markdown report. |
| `--output-dir` | `string` | `"zigzag-reports"` | Directory to store generated reports. |
| `--json` | `bool` | `false` | Generate a JSON report alongside Markdown. |
| `--html` | `bool` | `false` | Generate an interactive HTML dashboard alongside Markdown. |
| `--llm-report` | `bool` | `false` | Enable LLM-powered report generation. |
| `--llm-max-lines` | `number` | `150` | Maximum number of lines for LLM report. |
| `--llm-description` | `string` | `null` | Optional description for LLM report. |
| `--port` | `number` | `N/A` | Port for serving the HTML dashboard. |
| `--log` | `bool` | `false` | Enable logging. |
| `--open` | `bool` | `false` | Automatically open the HTML report in a browser. |

## Config Loading Priority

Settings are applied from lowest to highest priority (later values win):

1. Hard-coded defaults
2. `zig.conf.json` (when using `zigzag run`)
3. CLI flags (always override file config)

When the first `--path` CLI flag is encountered, all file-loaded paths are replaced. Same for `--ignore`. Scalar fields (skip_cache, watch, etc.) always take the last CLI value.

## Ignore Patterns

ZigZag supports multiple ignore pattern types:

### Pattern Types

| Pattern Type | Example | Description |
|-------------|---------|-------------|
| **Wildcard Extension** | `*.png`, `*.svg`, `*.jpg` | Ignores all files with the specified extension (case-insensitive) |
| **Exact Filename** | `test.txt`, `config.json` | Ignores files with exact name match |
| **Wildcard Prefix** | `test*` | Ignores files starting with the prefix |
| **Wildcard Suffix** | `*config` | Ignores files ending with the suffix |
| **Directory Name** | `node_modules`, `.cache` | Ignores directories and all their contents |

### Auto-Ignored Items

ZigZag automatically ignores common build artifacts and system directories:

- `node_modules` (and all subdirectories like `.bin`)
- `.git`, `.svn`, `.hg`
- `.cache`
- `__pycache__`, `.pytest_cache`
- `target`, `build`, `dist`
- `.idea`, `.vscode`
- `.DS_Store`

### Binary File Detection

Binary files are automatically detected and excluded using:

1. **Extension-based detection** (fast path):
   - Images: `.png`, `.jpg`, `.jpeg`, `.gif`, `.bmp`, `.ico`, `.webp`
   - Archives: `.zip`, `.tar`, `.gz`, `.7z`, `.rar`
   - Executables: `.exe`, `.dll`, `.so`, `.dylib`
   - Media: `.mp3`, `.mp4`, `.avi`, `.mov`, `.mkv`
   - Fonts: `.woff`, `.woff2`, `.ttf`, `.otf`, `.eot`
   - Compiled: `.class`, `.jar`, `.pyc`, `.o`, `.a`
   - Documents: `.pdf`
   - Databases: `.db`, `.sqlite`

2. **Content-based detection** (fallback):
   - Checks for null bytes
   - Analyzes non-printable character ratio
   - Examines first 512 bytes for performance

## Output Format

Each processed directory contains a `report.md` file (or your custom `--output` filename) with the following structure:

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

Watch mode uses OS-level filesystem events (inotify on Linux, kqueue on macOS/BSD, ReadDirectoryChangesW on Windows) to detect changes instantly. Only the changed file is re-read from disk; the report is rebuilt from the in-memory state of all other files.

Events are debounced: rapid changes within a 50 ms window are batched into a single report write. Press `Ctrl+C` to stop.

## JSON Output

Pass `--json` (or set `"json_output": true` in `zig.conf.json`) to generate a machine-readable JSON report alongside the markdown file. The JSON file is written to the same directory with `.json` replacing the `.md` extension (e.g. `report.json` next to `report.md`).

### JSON Report Structure

```json
{
  "meta": {
    "version": "0.11.0",
    "generated_at_ns": 1738245534000000000,
    "scanned_paths": ["./src"]
  },
  "summary": {
    "source_files": 12,
    "binary_files": 3,
    "total_lines": 1450,
    "total_size_bytes": 58320,
    "languages": [
      { "name": "zig", "files": 10, "lines": 1300, "size_bytes": 52000 },
      { "name": "json", "files": 2, "lines": 150, "size_bytes": 6320 }
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

The JSON report is useful for CI dashboards, code analysis pipelines, or any tooling that needs structured metadata without parsing markdown.

## HTML Dashboard

Pass `--html` (or set `"html_output": true` in `zig.conf.json`) to generate a self-contained interactive HTML report alongside the markdown file. The HTML file is written next to the markdown with `.html` replacing `.md` (e.g. `report.html` next to `report.md`).

The dashboard is a **single `.html` file** with minimal dependencies — all CSS, JavaScript, and syntax highlighting assets are bundled. Open it directly in any browser.

### Dashboard Features

| Feature | Description |
|---------|-------------|
| **Summary cards** | Total files, lines, size, and languages at a glance |
| **Language chart** | Bar chart of file counts per language |
| **Size distribution** | Histogram of file sizes across the codebase |
| **File table** | Sortable, searchable table of all source files with path, language, size, and line count |
| **Source viewer** | Click any file to open a slide-in panel showing its source code |
| **Syntax highlighting** | Off-thread Prism highlighting for 20+ languages (Zig, Rust, Go, Python, JS/TS, C/C++, and more) |
| **Virtual scroll** | Files over 500 lines or 200 KB use a virtual-scrolling viewer — only visible lines are rendered, so even 10 000-line files open instantly |
| **Dark mode** | Follows the OS `prefers-color-scheme` setting automatically |

### Supported Languages (syntax highlighting)

Zig, JavaScript, TypeScript, Lua, JSON, HTML/XML/SVG, CSS, SCSS, Bash/Shell, C, C++, Rust, Go, Python, Ruby, Java, Markdown, TOML, YAML, SQL.

## Architecture

### Processing Pipeline

1. **Argument Parsing** → Configuration with ignore patterns
2. **Config File Loading** → `zig.conf.json` applied as base (when using `run`)
3. **Cache Initialization** → Load/validate cache, remove stale entries
4. **Thread Pool Setup** → Configure parallel workers
5. **Directory Traversal** → Walk each specified path
6. **File Filtering** → Apply ignore patterns and binary detection
7. **File Processing** → Read, cache, and collect metadata
8. **Report Generation** → Generate markdown with TOC and metadata
9. **Cleanup** → Save cache, free resources

### File Processing Decision Tree

```
File Encountered
    ├─→ In ignore patterns? → Skip (ignored_files++)
    ├─→ Auto-ignored directory? → Skip (ignored_files++)
    ├─→ Binary file (extension)? → Skip (ignored_files++)
    ├─→ Binary file (content)? → Skip (ignored_files++)
    ├─→ In cache and valid? → Use cached (cached_files++)
    └─→ Process and cache → Process (processed_files++)
```

## Cache System

**ZigZag** includes a smart caching system that:

- Persists between runs in `.cache/files/`
- Validates on startup to remove stale entries
- Uses file metadata (mtime, size) for change detection
- Performs atomic updates to prevent corruption
- Verifies cache consistency before shutdown

Cache location: `./.cache/` (relative to working directory)

### Cache Index Format

```
path|mtime|size|cache_filename
./src/main.zig|1738245534|2345|main.zig_a1b2c3d4
./src/utils.zig|1738245521|1024|utils.zig_e5f6g7h8
```

## Performance

### File Reading Strategies

ZigZag automatically selects the optimal reading strategy:

| File Size | Strategy | Description |
|-----------|----------|-------------|
| 0 - 1 MiB | `readFileAlloc` | Load entire file into memory |
| 1 - 16 MiB | `readFileMapped` | Memory-mapped I/O (platform-specific) |
| > 16 MiB | `readFileChunked` | Stream in chunks |

### Performance Tips

1. **Use cache**: Don't use `--skip-cache` unless necessary
2. **Tune thresholds**: Adjust `--small` and `--mmap` based on your file sizes
3. **Parallel processing**: More threads for large projects (auto-detected from CPU cores)
4. **Ignore patterns**: Use specific patterns to exclude unnecessary files early

## Testing

```bash
# Run all tests
zig build test

# Run specific test suite
zig test src/root.zig
```
### Statistics Categories

- **Cached**: Files read from cache (unchanged since last run)
- **Processed**: Files that were read and processed (new or modified)
- **Ignored**: Files excluded by patterns or binary detection

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing`)
5. Open a Pull Request

### Development Setup

```bash
# Clone repository
git clone https://github.com/LegationPro/zigzag.git
cd zigzag

# Build in development mode
zig build

# Run with debug logging
zig build run -- --path ./src

# Run tests
zig build test

# Format code
zig fmt src/
```

### Code Style

- Follow Zig's standard formatting (`zig fmt`)
- Write tests for new features
- Document public APIs
- Keep functions focused and readable

## License

MIT License - see `LICENSE.md` file for details.

## Acknowledgments

- Built with the Zig programming language
- Inspired by code documentation and reporting tools
- Thanks to all contributors and testers
- Special thanks to the Zig community for feedback and support

## Links

- [GitHub Repository](https://github.com/LegationPro/zigzag)
- [Issue Tracker](https://github.com/LegationPro/zigzag/issues)
- [Zig Language](https://ziglang.org/)

---

**Made with ❤️ using Zig**
