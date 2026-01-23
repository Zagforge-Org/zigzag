# Zig-Zag

<img src="assets/logo.png" alt="zig-zag logo" width="64" height="64">


### A high-performance Zig-based tool for generating comprehensive markdown reports of source code directories with intelligent caching and parallel processing.

## Overview

<b>Zig-Zag</b> recursively scans directories and generates detailed markdown reports containing all source code with metadata. Each report includes a table of contents, syntax-highlighted code blocks with language detection, and file metadata including size, modification time (with timezone support), and language identification.

## Features

- **Smart file reading strategies** optimized for different file sizes
    
- **Persistent caching system** with automatic validation and atomic updates
    
- **Parallel processing** with configurable thread pooling
    
- **Cross-platform compatibility** including Windows and Unix/Linux systems
    
- **Timezone-aware timestamps** with configurable offsets
    
- **Multi-path support** for processing multiple directories simultaneously
    
- **File ignoring patterns** for flexible exclusion rules
    

## Installation

### Prerequisites

- Zig compiler version 0.12.0 or later
    

### Building from Source

```bash

git clone https://github.com/LegationPro/zig-zag.git
cd zig-zag
zig build -Doptimize=ReleaseFast
```

The executable will be available at `zig-out/bin/zig-zag`.

# Quick Start

### Basic Usage

```bash

# Generate report for current directory
zig-zag

# Generate report for specific directories
zig-zag --path ./src --path ./lib

# Generate report with custom timezone (UTC+1)
zig-zag --path ./project --timezone +1

# Skip cache operations
zig-zag --path ./project --skip-cache
```

### Advanced Examples

bash

```
# Multiple paths with ignore patterns
zig-zag --path ./backend --path ./frontend --ignore "*.test.*"

# Tune performance thresholds (in KB)
zig-zag --path ./src --small 512 --mmap 8192

# Generate report with specific timezone offset
zig-zag --path ./src --timezone -5    # UTC-5 (Eastern Time)
zig-zag --path ./src --timezone +5:30 # UTC+5:30 (India Standard Time)
```

## Output Format

Each processed directory contains a `report.md` file with the following structure:

```md

# Code Report for: `./src`

Generated on: 2026-02-17

---

## Table of Contents
- [./src/main.zig](#./src/main.zig)
- [./src/utils.zig](#./src/utils.zig)
...

## File: `./src/main.zig`

**Metadata:**
- **Size:** 2.28 KB
- **Language:** zig
- **Last Modified:** 2026-01-23 10:38:54 (UTC+1)

```zig
const std = @import("std");
// ... file content

...
```

# Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `--path` | Path to process (can be used multiple times) | Current directory |
| `--ignore` | Ignore files matching pattern (e.g., "*.test.zig") | None |
| `--timezone` | Timezone offset from UTC (e.g., +1, -5, +5:30) | UTC |
| `--small` | Threshold for small files (bytes) | 1048576 (1MB) |
| `--mmap` | Threshold for memory-mapped files (bytes) | 16777216 (16MB) |
| `--skip-cache` | Skip cache operations | false |
| `--help` | Show help message | |
| `--version` | Show version information | |

# Architecture

## Processing Pipeline
1. **Argument Parsing** → Configuration
2. **Cache Initialization** → Load/validate cache
3. **Thread Pool Setup** → Configure parallel workers
4. **Directory Traversal** → Walk each specified path
5. **File Processing** → Read, cache, and collect metadata
6. **Report Generation** → Generate markdown with TOC
7. **Cleanup** → Save cache, free resources

# Cache System

<b>Zig-Zag</b> includes a smart caching system that:

- Persists between runs in `.cache/files/`
- Validates on startup to remove stale entries
- Uses file metadata (mtime, size) for change detection
- Supports large files with content hashing
- Performs atomic updates to prevent corruption

Cache location: `./.cache/` (relative to working directory)

## Testing

```bash
# Run all tests
zig build test

# Run specific test suite
zig test src/cli_integration.zig
```

# Benchmarks

Compare file reading strategies:

zig build run-benchmark

# Contributing

1. Fork the repository
    
2. Create a feature branch (`git checkout -b feature/amazing`)
    
3. Commit changes (`git commit -m 'Add amazing feature'`)
    
4. Push to branch (`git push origin feature/amazing`)
    
5. Open a Pull Request
    

## Development Setup

```
bash

# Clone with submodules (if any)
git clone --recursive https://github.com/yourusername/zig-zag.git

# Build in development mode
zig build

# Run with debug logging
zig build run -- --path ./src --timezone +1
```

# License

MIT License - see LICENSE file for details.

## Acknowledgments

- Built with the Zig programming language
    
- Inspired by code documentation and reporting tools
    
- Thanks to all contributors and testers
