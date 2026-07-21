//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

/// Re-export the build options so version.zig can detect binary vs runtime mode.
/// Provided by build.zig (real version) or options_fallback.zig (0.0.0 sentinel).
pub const options = @import("options");

const builtin = @import("builtin");

test {
    // Every portable `*_test.zig` under src/ is auto-discovered by build.zig, which
    // regenerates src/test_manifest.zig on each build. Add a *_test.zig file and it is
    // picked up automatically.
    _ = @import("test_manifest.zig");

    // Non-test modules pulled in for compile-coverage under the test build.
    _ = @import("./cli/commands/config/Config.zig");
    _ = @import("./cli/commands/runner.zig");
    _ = @import("./platform/watcher.zig");

    // Platform-specific tests must stay gated on the target OS (the manifest excludes them).
    switch (builtin.os.tag) {
        .linux => {
            _ = @import("./platform/linux/Watcher_test.zig");
        },
        .macos, .freebsd, .netbsd, .openbsd, .dragonfly => {
            _ = @import("./platform/macos/Watcher_test.zig");
        },
        .windows => {
            _ = @import("./platform/windows/Watcher_test.zig");
        },
        else => {},
    }
}
