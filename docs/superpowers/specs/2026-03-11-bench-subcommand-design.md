# Design: `bench` Subcommand

**Date:** 2026-03-11
**Status:** Approved

---

## Overview

Add a `bench` subcommand to zigzag that runs the full scan-and-report pipeline with per-phase instrumentation and prints a timing breakdown table. Useful for identifying performance bottlenecks during development without modifying the normal run path.

```
zigzag bench --path ./some/project
zigzag bench                         # uses paths from zig.conf.json
```

---

## Goals

- Single-run, per-phase timing (scan, aggregate, write-md, write-json, write-html, write-llm)
- Per-phase context stats (file counts, output file sizes)
- `%` of total column for at-a-glance bottleneck identification
- Zero overhead on normal `zigzag run` — no timing code runs unless benchmarking

---

## Non-goals

- Multi-run averaging / warmup runs (can be added later)
- Machine-readable output (JSON bench results)
- Per-file granularity

---

## Architecture

Three touch points:

| What | Where | Change type |
|------|-------|-------------|
| `pub const BenchResult` | `src/cli/commands/runner.zig` | New exported struct |
| `bench: ?*BenchResult` param | `runner.exec()` + `writePathReports()` | New optional param |
| `src/cli/commands/bench.zig` | New file | `execBench()` + table printer |
| `src/main.zig` | Existing | Detect `bench` subcommand, dispatch |

---

## `BenchResult` Struct

Defined in `runner.zig`, exported as `pub`. All fields default to zero so `var b: BenchResult = .{}` requires no initializer.

```zig
pub const BenchResult = struct {
    // Phase durations in nanoseconds, accumulated across all paths
    scan_ns:        u64 = 0,
    aggregate_ns:   u64 = 0,
    write_md_ns:    u64 = 0,
    write_json_ns:  u64 = 0,
    write_html_ns:  u64 = 0,
    write_llm_ns:   u64 = 0,

    // Context for the stats column
    files_total:    usize = 0,
    files_source:   usize = 0,
    files_binary:   usize = 0,
    files_ignored:  usize = 0,
    md_bytes:       u64 = 0,
    json_bytes:     u64 = 0,
    html_bytes:     u64 = 0,
    llm_bytes:      u64 = 0,
};
```

Timing uses `std.time.nanoTimestamp()` deltas — no stored `Timer` in the struct. For multi-path runs all fields accumulate with `+=`.

---

## Instrumentation in `runner.zig`

Two functions gain a `bench: ?*BenchResult` parameter: the public `exec()` and the private `writePathReports()`.

### Timing helper (file-scoped)

```zig
inline fn nsElapsed(start: i128) u64 {
    return @intCast(std.time.nanoTimestamp() - start);
}
```

### `exec()` — scan phase

```zig
const t = std.time.nanoTimestamp();
const result = try scanPath(cfg, cache, path, &pool, allocator, logger);
if (bench) |b| {
    b.scan_ns       += nsElapsed(t);
    b.files_total   += result.file_entries.count() + result.binary_entries.count();
    b.files_source  += result.file_entries.count();
    b.files_binary  += result.binary_entries.count();
    b.files_ignored += result.ignored_count; // existing field on ScanResult
}
```

### `writePathReports()` — aggregate + write phases

```zig
// Aggregate
const t_agg = std.time.nanoTimestamp();
const data = try report.ReportData.init(...);
if (bench) |b| b.aggregate_ns += nsElapsed(t_agg);

// write-md
const t_md = std.time.nanoTimestamp();
try report.writeReport(...);
if (bench) |b| {
    b.write_md_ns += nsElapsed(t_md);
    b.md_bytes    += fileSizeOf(md_path);
}

// write-json (when cfg.json_output)
// write-html (when cfg.html_output)
// write-llm  (when cfg.llm_report)
// ... same pattern
```

`fileSizeOf(path)` is a file-scoped helper that calls `std.fs.cwd().statFile(path)` and returns `stat.size`, returning 0 on error.

### Existing callers

All existing callers of `runner.exec()` — `main.zig` and `watch.zig` — pass `null` as the new last argument. No behavioral change.

---

## `src/cli/commands/bench.zig`

```zig
const std = @import("std");
const Config = @import("config/config.zig").Config;
const CacheImpl = @import("../../cache/impl.zig").CacheImpl;
const runner = @import("runner.zig");

pub fn execBench(cfg: *const Config, allocator: std.mem.Allocator) !void {
    var cache = try CacheImpl.init(allocator, ".cache", cfg.small_threshold);
    defer cache.deinit();

    var result: runner.BenchResult = .{};
    try runner.exec(cfg, &cache, allocator, &result);
    printTable(allocator, &result);
}
```

### `printTable()`

Builds and prints the table to stderr using the existing colors infrastructure. Phases with zero duration are omitted (e.g. `write-html` when `--html` was not passed).

Example output:

```
  ─────────────────────────────────────────────────────────────
  Phase           Duration     Context              % Total
  ─────────────────────────────────────────────────────────────
  scan             340 ms      1,423 files            72%
  aggregate         12 ms      1,423 entries           3%
  write-md           8 ms         45 KB               2%
  write-json        60 ms        120 KB              13%
  write-html        45 ms        2.1 MB              10%
  ─────────────────────────────────────────────────────────────
  total            465 ms                           100%
```

- Duration formatted as `X ms` (sub-millisecond shown as `< 1 ms`)
- Context column: `files` for scan, `entries` for aggregate, human-readable bytes for writers
- `%` denominator is sum of all instrumented phases (not wall-clock total)

---

## `src/main.zig` Changes

Add `is_bench_command` detection alongside existing subcommands:

```zig
} else if (std.mem.eql(u8, arg, "bench")) {
    is_bench_command = true;
    is_run_command = true;  // reuse config-loading path (zig.conf.json + CLI flags)
```

Dispatch:

```zig
if (is_bench_command) {
    try bench.execBench(&cfg, allocator);
    return;
}
```

Setting `is_run_command = true` ensures `zig.conf.json` is loaded and CLI overrides apply — `zigzag bench --path ./myproject` and `zigzag bench` (config-file paths) both work without duplicating config logic.

---

## Help Text

Add `bench` to the commands section of `--help` output:

```
  bench           Run with per-phase timing instrumentation
```

---

## File Summary

| File | Action |
|------|--------|
| `src/cli/commands/runner.zig` | Add `BenchResult` struct; add `bench: ?*BenchResult` to `exec()` and `writePathReports()`; add timing blocks |
| `src/cli/commands/bench.zig` | New — `execBench()` + `printTable()` |
| `src/main.zig` | Add `bench` subcommand detection and dispatch |
| `src/cli/commands/help.zig` (or equivalent) | Add `bench` to commands list |

---

## Future Extensions

- `--runs N` flag: run N times and report mean ± stddev per phase
- `--warmup`: one uncounted run before timed runs (to warm filesystem cache)
- `--json`: emit bench results as JSON for CI regression tracking
- `dirs_total` field on `BenchResult` for directory traversal context
