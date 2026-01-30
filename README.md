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

### Basic Usage

```bash
# Generate report for current directory
zigzag --path .

# Generate report for specific directories
zigzag --path ./src --path ./lib

# Generate report with custom timezone (UTC+1)
zigzag --path ./project --timezone +1

# Skip cache operations
zigzag --path ./project --skip-cache
```

### Advanced Examples

```bash
# Ignore specific file extensions
zigzag --path ./src --ignore "*.png" --ignore "*.svg" --ignore "*.jpg"

# Ignore specific files
zigzag --path ./src --ignore "test.txt" --ignore "config.json"

# Multiple paths with ignore patterns
zigzag --path ./backend --path ./frontend --ignore "*.test.*" --ignore "node_modules"

# Tune performance thresholds (in bytes)
zigzag --path ./src --small 524288 --mmap 8388608

# Generate report with specific timezone offset
zigzag --path ./src --timezone -5    # UTC-5 (Eastern Time)
zigzag --path ./src --timezone +5:30 # UTC+5:30 (India Standard Time)
```

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

## Configuration Options

| Option | Description | Default | Example |
|--------|-------------|---------|---------|
| `--path` | Path to process (can be used multiple times) | Current directory | `--path ./src --path ./lib` |
| `--ignore` | Ignore pattern (can be used multiple times) | None | `--ignore "*.png" --ignore "test.txt"` |
| `--timezone` | Timezone offset from UTC | UTC (0) | `--timezone +1` or `--timezone -5:30` |
| `--small` | Threshold for small files (bytes) | 1048576 (1 MiB) | `--small 524288` |
| `--mmap` | Threshold for memory-mapped files (bytes) | 16777216 (16 MiB) | `--mmap 8388608` |
| `--skip-cache` | Skip cache operations and clear cache | false | `--skip-cache` |
| `--help` | Show help message with examples | - | `--help` |
| `--version` | Show version information | - | `--version` |

## Architecture

### Processing Pipeline

1. **Argument Parsing** → Configuration with ignore patterns
2. **Cache Initialization** → Load/validate cache, remove stale entries
3. **Thread Pool Setup** → Configure parallel workers
4. **Directory Traversal** → Walk each specified path
5. **File Filtering** → Apply ignore patterns and binary detection
6. **File Processing** → Read, cache, and collect metadata
7. **Report Generation** → Generate markdown with TOC and metadata
8. **Cleanup** → Save cache, free resources

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
- Supports large files with content hashing
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
```

### Code Style

- Follow Zig's standard formatting (`zig fmt`)
- Write tests for new features
- Document public APIs
- Keep functions focused and readable

## Roadmap

- [ ] Support for `.zigzagignore` file (like `.gitignore`)
- [ ] Regex-based ignore patterns
- [ ] Glob pattern support (`**/*.png`)
- [ ] MIME type detection for binary files
- [ ] Configurable binary detection threshold
- [ ] JSON output format option
- [ ] Progress bar for large projects
- [ ] Incremental report updates
- [ ] Language statistics summary

## License

MIT License - see LICENSE file for details.

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
