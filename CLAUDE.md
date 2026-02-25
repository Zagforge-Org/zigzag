# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ZigZag is a CLI tool written in Zig that recursively scans directories and generates markdown reports of source code. It uses parallel processing via a thread pool, a persistent file cache, and smart binary file detection.

Requires Zig `0.15.2` or later (set in `build.zig.zon`).

## Commands

```bash
# Development build
zig build

# Release build (output: zig-out/bin/zigzag)
zig build -Doptimize=ReleaseFast

# Run directly with arguments
zig build run -- --path ./src

# Run all tests
zig build test

# Run a specific test file directly
zig test src/cli/handlers.zig --summary all
zig test src/root.zig

# Format code
zig fmt src/

# Run benchmarks
zig build run-benchmark
```

## Architecture

### Entry Point & Config Parsing

`src/main.zig` is the entry point. It:
1. Collects CLI args and parses them via `Config.parse()` (`src/cli/commands/config.zig`)
2. Options are defined as `OptionHandler` structs in `src/cli/options.zig`, each with a handler function in `src/cli/handlers.zig`
3. Initializes the cache (`src/cache/impl.zig`) only when `--path` is provided
4. Delegates to `runner.exec()` (`src/cli/commands/runner.zig`)

### Processing Pipeline

`runner.exec()` → `processPath()` for each `--path`:
1. Creates a `WalkerCtx` holding shared state (thread pool, wait group, cache, stats, file entries map, mutex)
2. `Walk.walkDir()` (`src/fs/walk.zig`) recursively traverses the directory
3. For each file, `walkerCallback` (`src/walker/callback.zig`) spawns a `processFileJob` on the thread pool
4. After `wg.wait()`, the runner sorts and writes all collected entries to `report.md`

### Job Processing (`src/jobs/process.zig`)

`processFileJob` handles each file:
- Checks `shouldIgnore()` (auto-ignore list + user patterns)
- Stats the file; skips empty files
- Cache path: if file matches cache by `mtime` + `size`, reads from `.cache/files/`; otherwise reads from disk and updates cache
- Binary detection: extension-based first, then content heuristic (null bytes, >30% non-printable in first 512 bytes)
- Stores `JobEntry` in a shared `StringHashMap` under mutex

### Cache (`src/cache/impl.zig`)

`CacheImpl` maintains a `StringHashMap(CacheEntry)` in memory, backed by:
- `.cache/index` — pipe-delimited index (`path|mtime|size|cache_filename`)
- `.cache/files/` — one file per cached source file

On `init`: loads index from disk, validates entries against real file stats (removes stale). On `deinit`: saves index atomically (writes `.tmp` then renames), verifies consistency.

### Module Structure

```
src/
  main.zig                  # Entry point
  root.zig                  # Library root; references test files
  cli_integration.zig       # (integration layer)
  cli/
    options.zig             # OptionHandler array — maps CLI flags to handlers
    handlers.zig            # Handler functions + tests for each CLI option
    commands/
      config.zig            # Config struct, parse(), VERSION constant
      runner.zig            # processPath(), writeFileEntry(), exec()
      stats.zig             # ProcessStats with atomic counters
      writer.zig            # TProcessWriter type alias for callback
    context.zig             # FileContext (ignore list, md file, mutex)
    colors.zig, logo.zig    # Terminal color codes and ASCII logo
  cache/
    impl.zig                # CacheImpl — all cache logic
    entry.zig               # CacheEntry struct
  fs/
    walk.zig                # Walk — recursive directory traversal
    file.zig                # File reading strategies (alloc/mmap/chunked)
    mmap/                   # Platform-specific mmap (unix/, windows/)
    directory.zig           # Directory utilities
    directory_test.zig      # Directory tests
    stdout.zig              # stdoutPrint helper
    utils.zig               # Misc fs utilities
  jobs/
    job.zig                 # Job struct passed to thread pool
    entry.zig               # JobEntry (path, content, size, mtime, extension)
    process.zig             # processFileJob — ignore, cache, binary detect, store
  walker/
    callback.zig            # walkerCallback — spawns jobs onto pool
    context.zig             # WalkerCtx — shared state for walker + pool
  workers/
    pool.zig                # Thread pool implementation
    wait_group.zig          # WaitGroup for synchronization
  platform/
    windows/api.zig         # Windows-specific platform API
  benchmarks/
    file_benchmark.zig      # Benchmark suite
```

### Key Design Patterns

- **Option handler pattern**: each CLI flag has a statically-registered `OptionHandler` with `name`, `takes_value`, and a `handler` function pointer. Adding a new flag means adding an entry to the `options` array in `src/cli/options.zig` and implementing the handler in `src/cli/handlers.zig`.

- **Ignore patterns** are stored as a comma-joined string in `Config.ignore_patterns` and split in `processPath()` before being passed around. Pattern matching (`matchesPattern`) supports `*.ext`, `prefix*`, `*suffix`, and exact/path-contains matches.

- **Thread safety**: file entries are collected into a `StringHashMap` protected by `std.Thread.Mutex`. Stats use atomic operations (`fetchAdd`/`fetchSub`).

- **Tests** live inline in handler files (using `test "..." { ... }` blocks) and are wired into `zig build test` via `src/root.zig` and `build.zig`.
