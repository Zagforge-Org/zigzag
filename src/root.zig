//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

/// Re-export the build options so version.zig can detect binary vs runtime mode.
/// Provided by build.zig (real version) or options_fallback.zig (0.0.0 sentinel).
pub const options = @import("options");

test {
    _ = @import("./cli/handlers/version.zig");
    _ = @import("./cli/handlers/help.zig");
    _ = @import("./cli/handlers/skip_cache.zig");
    _ = @import("./cli/handlers/small.zig");
    _ = @import("./cli/handlers/mmap.zig");
    _ = @import("./cli/handlers/path.zig");
    _ = @import("./cli/handlers/ignore.zig");
    _ = @import("./cli/handlers/timezone.zig");
    _ = @import("./cli/handlers/watch.zig");
    _ = @import("./cli/handlers/output.zig");
    _ = @import("./cli/handlers/output_dir.zig");
    _ = @import("./cli/handlers/json.zig");
    _ = @import("./cli/handlers/html.zig");
    _ = @import("./cli/handlers/llm_report.zig");
    _ = @import("./cli/handlers/port.zig");
    _ = @import("./cli/commands/server.zig");

    _ = @import("./cli/commands/config.zig");
    _ = @import("./cli/commands/runner.zig");
    _ = @import("./cli/commands/report.zig");
    _ = @import("./cli/commands/watch.zig");
    _ = @import("./cli/version.zig");
    _ = @import("./cli/commands/stats.zig");

    // _ = @import("./conf/file.zig");
    _ = @import("./conf/file_test.zig");

    _ = @import("./fs/directory_test.zig");
    _ = @import("./fs/watcher.zig");
    _ = @import("./jobs/entry.zig");
    _ = @import("./jobs/process.zig");
}
