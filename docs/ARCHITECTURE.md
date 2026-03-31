# Project Architecture

This document describes the structure, responsibilities, and key design decisions across the ZigZag codebase.

---

## `/scripts`

The scripts folder contains code for running, building, debugging, and testing Zigzag binary builds.
It is an alternative to Makefile builds, if the user prefers to use Python instead of working with Makefile.
Python is used as a scripting language to solve:

- The strain of doing repetitive tasks in the terminal.
- Abstracting complex build commands that would be impossible to memorize.
- Ensuring tools that are required for contributions to the project are installed.

`setup.py` — Used as an entry script for bootstrapping the project, installing git modules, compiling source code, ensuring all tests are passing, and verifying all tools required for contributing and building the project are installed.

## `/src`

This folder consists of all the source code of Zigzag. Everything inside this folder is predominantly Zig.

## `/src/assets`

Contains assets used for the GitHub README.

## `/src/cache`

Contains code for the caching system. Each entry is a `CacheEntry` which holds metadata (`mtime`, `size`, `cache_filename`) for a given file. The cache automatically creates a `.cache` directory at the root of your project and is used for caching files to re-run projects at blazingly fast speeds. It is fully optimized for large codebases ranging from thousands to even hundreds of thousands of files. The cache is initialized on every run and automatically updates when code changes are detected. It automatically removes entries for files that have been moved or deleted. It is designed as an efficient disk storage system, where the format follows `path|mtime|size|cache_filename` pattern. Cache supports sanitized path components with limited length, hashes for uniqueness and prevents path collisions.

## `/src/cli/commands`

Contains code for the majority of the commands used to run the Zigzag engine.

- `bench` provides code for running benchmarks with cross-platform support in mind. Benchmarking is primarily used with caching, so for running benchmarks without a predefined cache, you would have to delete the existing `.cache` folder and rerun the command. The output shows a per-phase timing table (scan, aggregate, write-md, write-json, write-html, write-llm) with duration and percentage of total, alongside the machine info (OS, architecture, CPU), Zigzag version, and total execution time.

## `/src/cli/commands/config`

Contains all the configuration for CLI flags and predefined defaults. Handles configuration parsing with proper precedence, managing interactions between CLI flags and file-based configuration.

## `/src/cli/commands/report`

This folder contains all of the source code for working with different file formats and server-side event streaming. It supports: JSON, HTML, LLM-optimized Markdown, Markdown, and SSE.


The HTML section is written for outputting an HTML dashboard, used when the HTML flag or the JSON settings file specifies it. Its main priority is for visual purposes, and analytical data. It provides additional metadata to your project, which you would not see inside your typical IDE. (File size, last modified date, LOC (lines of code)). It uses the fnv1a32 algorithm for high-speed data storage and data retrieval, combined with the content.ts frontend implementation.

The JSON section is primarily written for writing JSON reports.

The LLM section is combined of several units:

- AST chunker
- Chunk writer
- LLM writer

The AST chunker is built on top of tree-sitter language extensions and handled through the C language. We are using C interoperability to connect the C language to our Zig implementation. It is mainly used for working with chunking for LLM's not to waste context, accurately splitting files across different chunks, and maintaining proper context for AI agents to understand the underlying code better.

The chunk writer is the building block for writing chunked files. Its main purpose is to write massive codebases into chunked files, which are optimized for LLMs to read.

The `llm.zig` is the source of the LLM-optimized implementation. Its purpose is to write a fully condensed LLM-optimized report alongside markdown reports.

The llm implementation:

- Filters out boilerplate from entries.
- Uses counting per-language files in LLM report.
- Builds sorted language list with proper sorting.
- Condenses file content.
- Writes files into chunks.
- Includes stats with proper headers and statistics.

The markdown section contains writing Markdown files with specified metadata directly into the markdown. The markdown is mostly used for documenting massive codebases, but can grow in size, if a project is massive.

The SSE section is a communication layer used exclusively in watch mode. It sends JSON payloads from the Zig side to the JavaScript side, where the JavaScript injects the data and streams it to the client in real-time. SSE is not used during regular report generation — it is only active when the `--watch` flag is enabled.


## `/src/cli/commands/runner`

The runner section is primarily used for performing path lookup reports, scanning codebases and working with provided flags that were given to the CLI. `reports.zig` is responsible for writing content to different format outputs. It also supports writing combined reports — when multiple paths are provided via the paths array in the configuration file or flags, it produces a combined report output on the dashboard with navigation across different paths.

The scan section is used to scan directory paths and collects entries efficiently in a concurrent environment in conjunction with the file walker.

## `/src/cli/commands/stats`

Contains `ProcessStats`, a struct that tracks file processing statistics across a run: `cached_files`, `processed_files`, `ignored_files`, and `binary_files`. All counters use atomic values for safe concurrent access. It also provides a `Summary` struct and a `getSummary` method that derives totals (total files, source files, etc.) from the atomic counters.

## `/src/cli/commands/watch`

The watch section implements event-driven watch mode using OS filesystem events (inotify on Linux, kqueue on macOS/BSD, ReadDirectoryChangesW on Windows) for incremental updates. It keeps all file content in memory and only re-processes changed files.

TTY detection (`isatty`) is used to suppress phase start/done lines during the initial scan — this prevents cursor-up rewrite corruption when the progress bar is active. Both TTY and non-TTY modes use the same logger otherwise.

If the configured port is already in use, the SSE server probes it via a non-blocking TCP connection check and increments the port, retrying up to 10 times. The port can also be set manually in the JSON settings file.

On macOS and BSD, kqueue `NOTE_WRITE` on a directory fd does not fire when an existing file is modified in-place — it only fires for creates, deletes, and renames. To compensate, the macOS watcher runs a periodic mtime scan every 2 seconds to catch in-place modifications. **This is a known platform limitation.**

The watch loop uses a 50ms debounce window to group rapid-fire filesystem events into a single update, preserving CPU resources and avoiding redundant report writes.

Per-path dirty flags ensure only the paths that actually received changes get their reports rebuilt on each debounce flush. On inotify queue overflow (events lost), all states are marked dirty and a full flush is triggered — rescanning is intentionally avoided on overflow to prevent creating further events that would overflow the queue again.

## `/src/cli/handlers/display`

The display section handles simple output commands.

- `help.zig` prints usage information for the Zigzag CLI.
- `logo.zig` provides an ASCII logo rendered in yellow, shown when the `zigzag` command is run with no flags and no subcommand.
- `version.zig` outputs the current version of the Zigzag CLI. The version is a compile-time constant baked into the binary via the `options` build module. When compiled outside the build system (e.g. during `zig test`), it falls back to `0.0.0`.

## `/src/cli/flags`

Defines the compile-time flag registry used by the config parser to dispatch CLI arguments to their handlers. Each entry is a `FlagsHandler` struct with three fields: `name` (the flag string, e.g. `--watch`), `takes_value` (whether it expects an argument), and `handler` (a function pointer into `/src/cli/handlers/flags/`). The `flags` array lists all supported flags and is the single source of truth for what the CLI accepts.

## `/src/cli/handlers/init`

Creates a `zig.conf.json` file with default configuration in the current working directory. If the file already exists and is non-empty, it prints a warning and exits. If the file exists but is empty, it overwrites it silently with the default configuration.

## `/src/cli/handlers/internal`

Contains test helpers. `test_config.zig` exposes a single `makeTestConfig` function that returns a `Config` initialised with default values via `Config.default(allocator)`, used across tests that need a baseline config without parsing CLI arguments.

## `/src/cli/handlers/upload`

** This section is under active development and is not yet production-ready. Expect bugs, code changes, and refactors when working with this flag. **

Contains integration with our cloud platform `Zagforge`.
`git_info.zig` defines the `GitInfo` struct (`commit_sha`, `branch`, `repo_full_name`, `org_slug`) and collects it by running `git` subprocesses against the current working directory. It also exposes `parseRepoFullName` which extracts the `org/repo` slug from a remote URL, supporting both HTTPS and SSH formats.

`upload.zig` POSTs a snapshot of each scanned path to the Zagforge API (`/api/v1/upload`). The payload is a minified JSON object containing git metadata (`org_slug`, `repo_full_name`, `commit_sha`, `branch`), a summary (`source_files`, `total_lines`), and a `file_tree` array where each entry includes the file path, language, line count, and a git blob SHA-1 computed over the file content.

The API key is resolved in order: `ZAGFORGE_API_KEY` env var, then `~/.zagforge/credentials`. The base URL defaults to the Zagforge Cloud endpoint but can be overridden via the `ZAGFORGE_API_URL` env var.

Each upload runs in a detached thread with a 30-second timeout. On timeout the thread is detached and the task memory is intentionally leaked to avoid a use-after-free. The arena allocator for each upload task is backed by `page_allocator` so upload-internal allocations never appear in the GPA.

## `/src/cli/version`

Handles version resolution for the Zigzag CLI. `version.zig` exposes `getVersion` which returns the version string in two modes:

- **Binary mode**: if a real version was baked in at compile time via the `options` build module (i.e. not `0.0.0`), it returns that string directly.
- **Runtime mode**: if the version is `0.0.0` or the `options` module is absent (e.g. `zig run`, `zig test`), it falls back to reading and parsing `build.zig.zon` from the current working directory.

`isRuntime()` detects which mode is active. `fallback.zig` is a stub `options` module that sets version to `0.0.0`, used when compiling outside the build system to trigger the runtime fallback path.

## `/src/conf`

Contains `FileConf`, the data structure that mirrors `zig.conf.json`. All fields are optional — any field absent from the file falls back to the defaults in `Config`. Key methods:

- `default()` — returns the default config as a static JSON string.
- `writeDefaultConfig()` — writes the default config to a given file path.
- `load()` — loads and parses `zig.conf.json` from the current working directory. If the file is empty, it parses the default JSON instead of returning an error.
- `loadFromPath()` — same as `load()` but accepts an explicit path. Empty files fall back to the default JSON.
- `loadFromPathEmpty()` — like `loadFromPath()` but returns `null` for empty files instead of falling back.
- `isEmpty()` — returns true if a file's content is entirely whitespace.

## `/src/fs`

Contains file and directory utilities used throughout the codebase:

- `file.zig` — file reading with three strategies: allocate into memory (small files ≤16 MiB), memory-map (medium files), or stream in 8 KiB chunks (very large files). `readFileAuto` selects the strategy automatically based on file size.
- `directory.zig` — `isDirectory()` helper with a Windows-specific workaround where `statFile` on a directory returns `IsDir` instead of a stat result.
- `stdout.zig` — `stdoutPrint()`, a buffered stdout writer with a 1 KiB stack buffer.
- `utils.zig` — `exists()`, a simple path existence check via `access`.
- `walk.zig` — parallel directory walker that dispatches subtrees to a worker pool.

## `/src/fs/mmap`

Implements memory-mapped file reading for Unix and Windows. `common.zig` defines shared errors (`EmptyFile`, `MapViewFailed`, `MMapFailed`). The Unix implementation uses `mmap(2)` with `MAP_PRIVATE | PROT_READ`. The Windows implementation uses `CreateFileMappingW` and `MapViewOfFile` via the platform API bindings. Both return a slice over the mapped region and handle empty files gracefully by returning an empty slice.

## `/src/fs/watcher`

Implements OS-native filesystem change detection. Linux uses inotify, macOS and BSD use kqueue, and Windows uses `ReadDirectoryChangesW`. Each platform has its own implementation file (`linux.zig`, `macos.zig`, `windows.zig`) selected at compile time via `watcher.zig`. The macOS implementation supplements kqueue with a periodic 2-second mtime scan because kqueue `NOTE_WRITE` does not fire on in-place file modifications. All three implementations share the same `WatchEvent` interface (`path`, `kind`) so the watch mode code is platform-agnostic.

## `/src/jobs`

Contains the per-file processing pipeline dispatched to the worker pool.

- `entry.zig` — defines the two result types: `JobEntry` (source file: path, content, size, mtime, extension, line count) and `BinaryEntry` (binary file: path, size, mtime, extension). `JobEntry` also provides `getLanguage()`, `formatSize()`, and `formatMtime()` helpers used by the report writers.
- `job.zig` — defines `Job`, the context struct passed to each worker: file path, cache pointer, stats counters, shared entry maps, a mutex to guard map writes, and two allocators (general and per-thread arena).
- `process.zig` — `processFileJob` is the core processing function. For each file it: checks ignore patterns and skip dirs, stats the file, reads content via the cache (or directly if uncached), detects binary files by extension and by a null-byte / non-printable character heuristic (>30% of first 512 bytes), counts lines, and inserts the result into either `file_entries` or `binary_entries` under the entries mutex.

## `/src/platform`

Contains OS-specific API bindings. Currently only Windows is covered, with two files in `/src/platform/windows/`:

- `api.zig` — binds `CreateFileMappingW`, `MapViewOfFile`, `CloseHandle`, and `UnmapViewOfFile` from `kernel32.dll`, used by the Windows mmap implementation.
- `watch.zig` — binds `CreateFileW` and `ReadDirectoryChangesW` from `kernel32.dll`, used by the Windows filesystem watcher.

## `/src/templates`

Contains the TypeScript source and build pipeline for the HTML dashboard. `bundle.py` drives the build: it runs `npm install` if needed, compiles TypeScript via esbuild into `dist/`, then injects the bundled JS and CSS directly into `template.html` to produce two self-contained output files — `dashboard.html` (single-path report) and `combined-dashboard.html` (multi-path combined report).

Key components in `src/`:

- `virtual-table.ts` — virtualized file table with 40px row height and overscan, so the dashboard stays responsive even with hundreds of thousands of files.
- `highlight.worker.ts` — Prism.js syntax highlighting running in a Web Worker to keep the main thread unblocked.
- `watch.ts` — SSE client that connects to the Zig-side SSE server, receives JSON payloads, and live-updates the dashboard without a page reload.
- `charts.ts` — language and file size distribution charts.
- `combined.ts` / `combined-types.ts` — logic for the multi-path combined dashboard view.
- `theme.ts` — light/dark theme toggle with persistence.

## `/src/utils`

Single-entry-point utility module — `utils.zig` re-exports everything. Sub-modules:

- `colors/` — `Color` enum and `colorCode()` returning ANSI escape sequences for 16 standard colors plus Reset.
- `fmt/` — two formatting helpers: `fmtBytes` (formats a byte count into B/KB/MB with optional HTML content suffix) and `fmtElapsed` (formats nanosecond durations into `< 1ms`, `42ms`, or `1.50s`).
- `logger/` — facade re-exporting the full logger surface:
  - `print/` — `printStep`, `printSuccess`, `printError`, `printWarn`, `printSeparator` for colored stderr output.
  - `summary/` — `printSummary` prints a per-path file count block (total, source, cached, fresh, binary, ignored) to stderr; suppressed on TTY where the progress bar already shows the count.
  - `phase/` — `printPhaseStart` / `printPhaseDone` for TTY-aware phase timing lines with cursor-up rewrite; `printFinalSummary` prints the full post-run report (summary, phase breakdown, generated reports, highlights).
  - `cpu/` — `getCpuName` reads the CPU model string for display in bench/summary output.
  - `file_logger/` — `Logger`, a file-backed logger for writing debug output to disk.
- `progress/` — `ProgressBar` runs a spinner (first ~1s) then a rolling-estimate block bar in a background thread, updating at 100ms intervals. Stops cleanly on `stop()` and writes a final scanned-file success line.
- `skip_dirs/` — `DEFAULT_SKIP_DIRS`, the compile-time list of directory names skipped by both the file walker and the watcher (e.g. `node_modules`, `.git`, `.zig-cache`).


## `/src/walker`

Bridges the directory walker and the worker pool.

- `context.zig` — defines `WalkerCtx`, the shared context threaded through every walker callback. Holds references to the pool, wait group, file context, cache, stats counters, entry maps, mutex, allocator, and a semaphore capped at 64 permits to prevent file descriptor exhaustion when walking deep directory trees concurrently.
- `callback.zig` — `walkerCallback` is called by `fs/walk.zig` for each discovered file. It duplicates the path, constructs a `Job`, and dispatches it to the pool via `spawnWg` — connecting the walker to the job processing pipeline.

## `/src/workers`

Low-level concurrency primitives.

- `pool.zig` — `Pool` is a thread pool backed by a mutex-protected doubly-linked run queue. Workers block on a condition variable and wake on `cond.signal()`. Each worker owns a per-thread `ArenaAllocator` that is reset between jobs (`retain_capacity`) for O(1) allocation without syscalls. `spawnWg` enqueues a typed closure and increments the `WaitGroup` counter; falls back to inline execution on `builtin.single_threaded` or on allocation failure. Thread count defaults to CPU count. Optionally tracks thread IDs.
- `wait_group.zig` — `WaitGroup` is a mutex + condition variable counter. `start()` increments, `finish()` decrements and broadcasts when it reaches zero, `wait()` blocks until zero, `isDone()` checks non-blocking.

---

## `/ast`

The `ast/` directory is a self-contained AST chunking library used by the LLM report writer to split source files into semantically meaningful chunks (functions, classes, etc.) rather than arbitrary byte boundaries.

### Architecture

The library is built in two layers:

- **C layer** (`ast/src/chunker.c` + `chunker.h`) — core parsing logic using the tree-sitter runtime. Exposes two functions: `extract_chunks()` which parses a source string and returns an array of line ranges, and `free_chunk_result()` which frees the allocated result.
- **Zig layer** (`src/cli/commands/report/writers/llm/ast_chunker.zig`) — declares `extern fn` bindings for the C functions, maps file extensions to tree-sitter language initializers and node type lists, and exposes a high-level `chunkSource()` function that returns `?[]Chunk`.

Zig never inspects tree-sitter internals — language pointers are typed as `opaque {}` and only passed through to the C layer.

### How chunking works

`extract_chunks()` parses source code into a tree-sitter AST and walks only the **top-level** children of the root node. Any node whose type matches the configured list (e.g. `function_definition`, `class_declaration`) is recorded as a chunk with its start and end line numbers (0-based). The chunk array grows dynamically starting at capacity 16, doubling as needed.

### Supported languages (18)

Python, JavaScript, TypeScript, TSX, Rust, Go, C, C++, Java, C#, Ruby, Elixir, Kotlin, Swift, Lua, Bash, PHP, Zig.

### Dependencies

- `ast/vendor/tree-sitter/` — tree-sitter runtime (git submodule, sparse-checked out to `lib/` only in CI).
- `ast/grammars/tree-sitter-<lang>/` — one git submodule per language (sparse-checked out to `src/` only in CI).

### Build integration

The grammars and chunker are compiled as C object files by `zig cc` (see CI workflow and `build.zig`), archived into `.zig-cache/ts_ast.a`, and linked into the main Zigzag binary. This means the AST library adds no runtime dependencies — everything is statically linked.

### Adding a new language

See `ast/docs/add_grammar.md` for the full checklist: adding the git submodule, updating `CMakeLists.txt`, `build.zig`, `Makefile`, `scripts/setup.py`, the CI workflow sparse-checkout steps, and the `ast_chunker.zig` extern declarations and extension mapping.