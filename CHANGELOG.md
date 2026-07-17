# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/Zagforge-Org/zigzag/compare/v0.19.0...HEAD
[0.19.0]: https://github.com/Zagforge-Org/zigzag/compare/v0.18.0...v0.19.0
