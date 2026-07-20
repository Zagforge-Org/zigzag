# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.20.0] - 2026-07-20

Watch-mode performance and correctness overhaul, measured against a Next.js-sized
repository (~82k files, ~25.6k source files, with JSON, HTML, and LLM output all
enabled):

| Metric | 0.19.0 | 0.20.0 |
|---|---|---|
| Startup to usable dashboard | 3 min 32 s | **0.7 s** |
| File change → SSE delta in browser | 40 ms when idle; up to ~45 s during flushes, sometimes lost | **11–105 ms, always** |
| Deltas delivered during an 8-edit burst | 2 of 8 | **8 of 8** |
| Debounce flush (report rewrite) | 35–45 s, blocking event handling | ~2–4 s, on a background thread |
| Memory across repeated edits | +~100 MB per edit, unbounded | **flat** |

### Changed
- **Watch mode no longer blocks on report writing.** The debounce flush
  (markdown, JSON, HTML, LLM reports) runs on a dedicated background thread;
  the watch loop keeps polling filesystem events and pushing SSE deltas while
  reports are written. Writers consume an immutable snapshot taken under the
  entries lock, with a deferred-free window keeping snapshot contents valid
  while concurrent events retire entries.
- **Startup is server-first.** The SSE server binds immediately after the scan,
  only the dashboard HTML is written synchronously (with the final port baked
  into its `sse_url`), and the full report suite runs as the first background
  flush. On large repositories the dashboard now serves in well under a second;
  markdown/JSON/LLM output lands a few seconds later.
- **LLM report generation is incremental.** Condensed/AST-chunked results are
  memoized per file and reused while the file's mtime is unchanged, so a flush
  re-condenses only what changed; the cold first pass fans out across the
  worker pool. This also keeps watch-mode memory flat (previously ~100 MB of
  RSS growth per edit on large repositories).
- Content sidecar writes skip files whose sidecar is already newer than the
  source (make-style staleness), and the cache index is written in a single
  buffered write instead of one syscall per entry.
- Internal restructuring across the codebase: file-structs for
  `State`/`Server`/`WatchLoop`/`Stats`/`ReportData`/`Pool`/`WaitGroup`/`Job`/
  `ChunkWriter`/`Cache`, command facades for `runner` and `serve`, a
  modularized logger, and modularized HTML/LLM report writers.

### Fixed
- The dashboard port probe uses a bounded (250 ms) connect timeout. A plain
  blocking probe could hang startup for ~2 minutes on hosts that silently drop
  loopback SYNs to unbound ports (observed on WSL2).
- SSE per-file deltas queue in order and are all delivered; previously a full
  snapshot broadcast landing in the same tick could silently displace a queued
  delta, losing dashboard updates during rapid edits.
- The SSE event loop bounds its request-header read (2 s); an accepted
  connection that never sent data (browser preconnect, port scan, loopback
  relay) could previously freeze all dashboard updates indefinitely.
- macOS: the mtime fallback scan (the only way in-place file edits are detected
  under kqueue) now sweeps every watched directory each cycle instead of
  rotating through 256-directory batches, bounding detection latency to one
  interval (~2 s) instead of minutes on large trees (~105 s on a ~13k-directory
  checkout). The interval stretches adaptively when a sweep measures slow.
  Covered by a regression test and macOS cross-compilation; not yet exercised
  on macOS hardware outside CI.

### Added
- Regression tests: repeated-flush leak check (all outputs enabled),
  deferred-free flush window, SSE delta FIFO semantics, macOS full-sweep
  coverage, and watch-loop dirty-set handling.
- CI can be triggered manually on any branch via `workflow_dispatch` (useful
  for running the macOS test job before merging).

### Known trade-offs
- Report files intentionally lag edits by a few seconds: the dashboard is fed
  by SSE deltas while markdown/JSON/LLM output lands when the background flush
  catches up. On a first-ever run they appear shortly after startup rather than
  before it.
- The LLM memo holds one condensed working set resident (~100 MB on a
  Next.js-sized tree) — a deliberate speed-for-memory trade.

## [0.19.0] - 2026-07-17

### Changed
- Migrated the entire codebase to the new `Io` interface introduced in Zig
  0.16.0. Filesystem, networking, process, and threading operations now flow
  through a single runtime `Io` handle rather than the removed `std.fs`,
  `std.net`, and `std.Thread` blocking APIs.
  - Environment variables are read from the process environment passed to
    `main` (`rt.getEnv`) instead of the removed `std.process.getEnvVarOwned`.
  - The `serve` and `watch` HTTP/SSE servers were rewritten on top of
    `std.Io.net`; the port-availability probe was reimplemented accordingly.
  - inotify watching and raw file-descriptor handling use `std.os.linux`
    syscalls directly, since the corresponding `std.posix` wrappers were removed.
- **Minimum supported Zig version is now 0.16.0** (was 0.15.2).
- The build now compiles through the LLVM backend (`use_llvm = true`). The
  self-hosted x86 backend cannot yet emit some relocations required by the
  linked C sources.

### Removed
- The `--upload` flag and the Zagforge snapshot upload feature, along with its
  `upload` configuration option. The feature was unfinished and is no longer
  part of the tool.

## Previous releases

Release history prior to 0.19.0 is available from the
[git tags](https://github.com/Zagforge-Org/zigzag/tags).

[Unreleased]: https://github.com/Zagforge-Org/zigzag/compare/v0.20.0...HEAD
[0.20.0]: https://github.com/Zagforge-Org/zigzag/compare/v0.19.0...v0.20.0
[0.19.0]: https://github.com/Zagforge-Org/zigzag/compare/v0.18.0...v0.19.0
