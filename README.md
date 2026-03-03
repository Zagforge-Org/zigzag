# ZigZag

<img src="assets/logo.png" alt="zig-zag logo" width="64" height="64">

### A high-performance Zig-based tool for generating comprehensive markdown reports of source code directories with intelligent caching, parallel processing, and smart binary file detection.

## Overview

**ZigZag** recursively scans directories and generates detailed markdown reports containing all source code with metadata. Each report includes a table of contents, syntax-highlighted code blocks with language detection, and file metadata including size, modification time (with timezone support), and language identification. Binary files are automatically detected and excluded to maintain clean, readable reports.

## Features

- **Smart file reading strategies** optimized for different file sizes
- **Intelligent binary file detection** prevents corrupted markdown output
- **Flexible ignore patterns** supporting wildcards, extensions, and exact matches
- **Persistent caching system** with automatic validation and atomic updates
- **Parallel processing** with configurable thread pooling
- **Cross-platform compatibility** including Windows and Unix/Linux systems
- **Timezone-aware timestamps** with configurable offsets
- **Multi-path support** for processing multiple directories simultaneously
- **Auto-ignore common directories** (node_modules, .git, build artifacts)
- **JSON config file** (`zig.conf.json`) for project-level defaults
- **Watch mode** for continuous report regeneration on file changes
- **Configurable output filename** for the generated report
- **JSON report output** (`--json`) for machine-readable analytics alongside the markdown report
- **HTML dashboard** (`--html`) — interactive single-file report with charts, sortable file table, search, and a virtual-scrolling source viewer with syntax highlighting

## Installation

### Prerequisites

- Zig compiler version 0.15.2 or later

### Building from Source

```bash
git clone https://github.com/LegationPro/zigzag.git
cd zigzag
zig build -Doptimize=ReleaseFast
```

The executable will be available at `zig-out/bin/zigzag`.

## Quick Start

### Initialize a project

```bash
# Create zig.conf.json with default values in the current directory
zigzag init
```

### Run from config file

```bash
# Run using paths and options from zig.conf.json
zigzag run

# Run from config file, overriding specific options via CLI flags
zigzag run --path ./src --ignore "*.test.zig"
zigzag run --watch
```

### Basic ad-hoc usage

```bash
# Generate report for a specific directory
zigzag --path ./src

# Multiple paths with ignore patterns
zigzag --path ./backend --path ./frontend --ignore "*.test.*"

# Generate report with custom timezone (UTC+1)
zigzag --path ./project --timezone +1

# Custom output filename
zigzag --path ./src --output context.md

# Skip cache operations
zigzag --path ./project --skip-cache
```

### Advanced Examples

```bash
# Ignore specific file extensions
zigzag --path ./src --ignore "*.png" --ignore "*.svg" --ignore "*.jpg"

# Ignore specific files
zigzag --path ./src --ignore "test.txt" --ignore "config.json"

# Tune performance thresholds (in bytes)
zigzag --path ./src --small 524288 --mmap 8388608

# Generate report with specific timezone offset
zigzag --path ./src --timezone -5    # UTC-5 (Eastern Time)
zigzag --path ./src --timezone +5:30 # UTC+5:30 (India Standard Time)

# Watch mode — react instantly to file changes
zigzag --path ./src --watch

# Generate JSON report alongside markdown
zigzag --path ./src --json

# Generate interactive HTML dashboard alongside markdown
zigzag --path ./src --html
```

## Subcommands

| Command | Description |
|---------|-------------|
| `init`  | Creates `zig.conf.json` with default values in the current directory. No-ops if the file already exists. |
| `run`   | Loads `zig.conf.json` as the base config, then applies any CLI flags on top. Useful for project-level defaults. |

Without a subcommand, ZigZag applies CLI flags directly (no file config is loaded).

## Configuration File (`zig.conf.json`)

Running `zigzag init` creates a `zig.conf.json` in the current directory:

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
  "json_output": false,
  "html_output": false
}
```

### Config Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `paths` | `string[]` | `[]` | Directories to scan |
| `ignore_patterns` | `string[]` | `[]` | Ignore patterns (same syntax as `--ignore`) |
| `skip_cache` | `bool` | `false` | Skip cache operations and clear cache |
| `skip_git` | `bool` | `false` | Skip git operations |
| `small_threshold` | `number` | `1048576` | Small file threshold in bytes (1 MiB) |
| `mmap_threshold` | `number` | `16777216` | Memory-mapped file threshold in bytes (16 MiB) |
| `timezone` | `string\|null` | `null` | Timezone offset string (e.g. `"+1"`, `"-5:30"`) |
| `output` | `string` | `"report.md"` | Output filename for the generated report |
| `watch` | `bool` | `false` | Enable watch mode |
| `json_output` | `bool` | `false` | Emit a JSON report alongside the markdown report |
| `html_output` | `bool` | `false` | Emit an interactive HTML dashboard alongside the markdown report |

### Config Loading Priority

Settings are applied from lowest to highest priority (later values win):

1. Hard-coded defaults
2. `zig.conf.json` (when using `zigzag run`)
3. CLI flags (always override file config)

When the first `--path` CLI flag is encountered, all file-loaded paths are replaced. Same for `--ignore`. Scalar fields (skip_cache, watch, etc.) always take the last CLI value.

## CLI Options

| Option | Description | Default | Example |
|--------|-------------|---------|---------|
| `--path` | Path to process (repeatable) | — | `--path ./src --path ./lib` |
| `--ignore` | Ignore pattern (repeatable) | — | `--ignore "*.png" --ignore "test.txt"` |
| `--output` | Output filename | `report.md` | `--output context.md` |
| `--timezone` | Timezone offset from UTC | UTC (0) | `--timezone +1` or `--timezone -5:30` |
| `--small` | Threshold for small files (bytes) | 1048576 (1 MiB) | `--small 524288` |
| `--mmap` | Threshold for memory-mapped files (bytes) | 16777216 (16 MiB) | `--mmap 8388608` |
| `--skip-cache` | Skip cache operations and clear cache | false | `--skip-cache` |
| `--watch` | Watch for file changes and regenerate output | false | `--watch` |
| `--json` | Emit a JSON report alongside the markdown report | false | `--json` |
| `--html` | Emit an interactive HTML dashboard alongside the markdown report | false | `--html` |
| `--help` | Show help message with examples | — | `--help` |
| `--version` | Show version information | — | `--version` |

> **Note:** `skip_git` can only be set via `zig.conf.json`, not as a CLI flag.

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

### Ignore Examples

```bash
# Ignore all image files
zigzag --path ./src \
  --ignore "*.png" \
  --ignore "*.jpg" \
  --ignore "*.svg" \
  --ignore "*.gif"

# Ignore test files and build artifacts
zigzag --path ./project \
  --ignore "*.test.js" \
  --ignore "*.spec.ts" \
  --ignore "dist" \
  --ignore "coverage"

# Complex multi-pattern ignore
zigzag --path ./monorepo \
  --ignore "*.png" \
  --ignore "*.jpg" \
  --ignore "node_modules" \
  --ignore "*.log" \
  --ignore "temp*"
```

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

```bash
# Watch a directory — reacts within ~50 ms of any file change
zigzag --path ./src --watch

# Watch mode via config file
zigzag run --watch
```

Events are debounced: rapid changes within a 50 ms window are batched into a single report write. Press `Ctrl+C` to stop.

## JSON Output

Pass `--json` (or set `"json_output": true` in `zig.conf.json`) to generate a machine-readable JSON report alongside the markdown file. The JSON file is written to the same directory with `.json` replacing the `.md` extension (e.g. `report.json` next to `report.md`).

```bash
zigzag --path ./src --json
zigzag run --json
```

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

```bash
zigzag --path ./src --html
zigzag run --html
```

The dashboard is a **single `.html` file** with no external dependencies — all CSS, JavaScript, and syntax highlighting assets are bundled inline. Open it directly in any browser.

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

### Benchmarks

Run the included benchmark suite:

```bash
zig build run-benchmark
```

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

# Test with debug output
zig test src/cli/handlers.zig --summary all
```

### Test Coverage

- Configuration parsing and validation
- Ignore pattern matching (wildcards, extensions, exact matches)
- Timezone offset handling
- Binary file detection
- Cache operations and consistency
- Directory traversal
- Config file loading and CLI override behavior

## Processing Statistics

After processing, ZigZag displays a summary:

```
=== Summary for ./src ===
=== Processing Summary ===
Total files: 42
Cached (from .cache): 35
Processed (updated): 5
Ignored: 2
```

### Statistics Categories

- **Cached**: Files read from cache (unchanged since last run)
- **Processed**: Files that were read and processed (new or modified)
- **Ignored**: Files excluded by patterns or binary detection

## Troubleshooting

### Common Issues

**Q: Binary files still appearing in report**
- A: Ensure you're using the latest version with binary detection. Check file extensions are in the binary list.

**Q: Ignore patterns not working**
- A: Use quotes around patterns: `--ignore "*.png"` not `--ignore *.png`
- Check pattern syntax: `*.ext` for extensions, exact names for files

**Q: node_modules/.bin still included**
- A: This is fixed in the latest version. Rebuild from source.

**Q: Cache taking up too much space**
- A: Run with `--skip-cache` once to clear, or manually delete `.cache` directory

**Q: Timezone not displaying correctly**
- A: Use format `+H` or `+H:MM`. Examples: `+1`, `-5`, `+5:30`

**Q: zig.conf.json settings not being picked up**
- A: Use `zigzag run` (not `zigzag --path ...`) to load the config file. Plain flags bypass file config.

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

## Roadmap

- [ ] Regex-based ignore patterns
- [ ] Glob pattern support (`**/*.png`)
- [ ] MIME type detection for binary files
- [ ] Configurable binary detection threshold
- [ ] Progress bar for large projects
- [ ] Incremental report updates

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
