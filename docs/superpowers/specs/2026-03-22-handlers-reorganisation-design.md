# Handlers Reorganisation — Design Spec
_Date: 2026-03-22_

## Problem

`src/cli/handlers/` is a flat directory of 24 files covering four distinct concerns: pure config-flag setters, stdout display, filesystem writes, and HTTP/subprocess networking. Tests are written inline inside source files, which diverges from the `_test.zig` convention used everywhere else in the codebase (report/, config/, runner/, watch/).

## Goals

1. Split handlers into subfolders by responsibility so each folder has a single, obvious purpose.
2. Move all inline tests to separate `_test.zig` files, matching the project-wide convention.
3. Keep all 293 existing tests passing with no behaviour changes.

---

## New Directory Structure

```
src/cli/handlers/
├── flags/          Pure *Config flag setters (one file per CLI flag)
│   ├── chunk_size.zig        chunk_size_test.zig
│   ├── html.zig              html_test.zig
│   ├── ignore.zig            ignore_test.zig
│   ├── json.zig              json_test.zig
│   ├── llm_report.zig        llm_report_test.zig
│   ├── log.zig               log_test.zig
│   ├── mmap.zig              mmap_test.zig
│   ├── no_watch.zig          no_watch_test.zig
│   ├── open.zig              open_test.zig
│   ├── output.zig            output_test.zig
│   ├── output_dir.zig        output_dir_test.zig
│   ├── path.zig              path_test.zig
│   ├── port.zig              port_test.zig
│   ├── skip_cache.zig        skip_cache_test.zig
│   ├── small.zig             small_test.zig
│   ├── timezone.zig          timezone_test.zig
│   ├── upload.zig            upload_test.zig   ← sets cfg.upload = true only
│   └── watch.zig             watch_test.zig
├── display/        Print-to-stdout handlers (no Config mutation)
│   ├── help.zig              help_test.zig
│   ├── logo.zig              (no tests)
│   └── version.zig           version_test.zig
├── upload/         HTTP upload + git subprocess logic
│   ├── upload.zig            upload_test.zig
│   └── git_info.zig          git_info_test.zig
├── init/           Filesystem: writes zig.conf.json to disk
│   └── init.zig              init_test.zig
└── internal/       Test helpers — never imported by production code
    └── test_config.zig
```

### Design note: flags/upload.zig vs upload/upload.zig

The `--upload` CLI flag is a pure config setter (`cfg.upload = true`) and belongs in `flags/`. The actual HTTP logic (`performUpload`, `getApiKey`, `resolveUploadUrl`, `gitBlobSha`) lives in `upload/upload.zig`. `flags/upload.zig` does **not** import from `upload/`; the runner imports `upload/upload.zig` directly. This keeps `flags/` pure.

**Critical:** `src/cli/flags.zig` must import `handleUpload` from `./handlers/flags/upload.zig`. It must **not** import from `./handlers/upload/upload.zig`.

---

## Import Path Changes

### External callers

| File | Symbol | Old path | New path |
|---|---|---|---|
| `src/cli/flags.zig` | all 18 flag handlers incl. `uploadHandler` | `./handlers/<name>.zig` | `./handlers/flags/<name>.zig` |
| `src/cli/flags.zig` | `helpHandler`, `versionHandler` | `./handlers/help.zig`, `./handlers/version.zig` | `./handlers/display/help.zig`, `./handlers/display/version.zig` |
| `src/main.zig` | `initHandler` | `./cli/handlers/init.zig` | `./cli/handlers/init/init.zig` |
| `src/main.zig` | `printAsciiLogo` | `./cli/handlers/logo.zig` | `./cli/handlers/display/logo.zig` |
| `src/cli/commands/runner.zig` | `upload_mod` | `../handlers/upload.zig` | `../handlers/upload/upload.zig` |

### Internal path shift rule

Each source file moves down one directory level. All relative imports gain one `../` prefix. The full import map per folder is:

#### `flags/*.zig`
| Import | New path |
|---|---|
| Config | `../../commands/config/config.zig` |
| test_config (test files only) | `../internal/test_config.zig` |
| utils | `../../../utils/utils.zig` |

#### `display/*.zig`
| Import | New path |
|---|---|
| Config | `../../commands/config/config.zig` |
| test_config (test files only) | `../internal/test_config.zig` |
| utils | `../../../utils/utils.zig` |
| fs/stdout | `../../../fs/stdout.zig` |

#### `upload/upload.zig`
| Import | New path |
|---|---|
| Config | `../../commands/config/config.zig` |
| ScanResult (runner) | `../../commands/runner/scan.zig` |
| git_info | `./git_info.zig` (sibling — unchanged) |
| utils | `../../../utils/utils.zig` |

#### `upload/git_info.zig`
No import path changes needed — this file only imports `std`.

#### `init/init.zig`
| Import | New path |
|---|---|
| conf/file | `../../../conf/file.zig` |
| utils | `../../../utils/utils.zig` |

#### `internal/test_config.zig`
| Import | New path |
|---|---|
| Config | `../../commands/config/config.zig` |

---

## Test Extraction Convention

Every source file loses its `test` blocks and any test-only imports (`const testing = std.testing`, `const makeTestConfig = ...`). Tests move to a sibling `_test.zig` file.

**Pattern** (example: `flags/no_watch_test.zig`):
```zig
const std = @import("std");
const handleNoWatch = @import("./no_watch.zig").handleNoWatch;
const makeTestConfig = @import("../internal/test_config.zig").makeTestConfig;

test "handleNoWatch disables watch mode" { ... }
```

Files with no tests (`logo.zig`, `test_config.zig`) get no `_test.zig` counterpart.

---

## root.zig Changes

The 21 handler source imports that currently relied on inline test discovery are removed. 23 explicit `_test.zig` imports replace them (one per tested file across all subfolders).

```zig
// REMOVED (21 handler source imports — inline test discovery)
_ = @import("./cli/handlers/version.zig");
_ = @import("./cli/handlers/no_watch.zig");
// ... 19 more

// ADDED (23 explicit _test.zig imports)
// flags/ — 18 files
_ = @import("./cli/handlers/flags/chunk_size_test.zig");
_ = @import("./cli/handlers/flags/html_test.zig");
// ... 16 more flags
// display/ — 2 files
_ = @import("./cli/handlers/display/help_test.zig");
_ = @import("./cli/handlers/display/version_test.zig");
// upload/ — 2 files
_ = @import("./cli/handlers/upload/upload_test.zig");
_ = @import("./cli/handlers/upload/git_info_test.zig");
// init/ — 1 file
_ = @import("./cli/handlers/init/init_test.zig");
```

---

## Pre-implementation check

Before executing: grep `src/build.zig` for any explicit references to files under `src/cli/handlers/`. The standard build uses `root.zig` as the test root and does not enumerate handler files individually — but this should be confirmed to avoid silent breakage.

---

## Files Affected Summary

| Category | Count | Action |
|---|---|---|
| Handler source files moved | 24 | Move to subfolder + update import paths |
| `_test.zig` files created | 23 | New files (tests extracted from source) |
| Source files with inline tests stripped | 23 | Remove `test` blocks + test-only imports |
| External callers updated | 3 | `flags.zig`, `main.zig`, `runner.zig` |
| `root.zig` | 1 | Replace 21 source imports with 23 `_test.zig` imports |

---

## Success Criteria

- `zig build` compiles cleanly.
- `make test` passes all 293 tests (no tests are added or removed — only relocated).
- No `test` block remains in any non-`_test.zig` handler file.
- No handler source file imports `std.testing` or `makeTestConfig` directly.
