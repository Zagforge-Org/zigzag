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

    _ = @import("./cli/commands/config/config.zig");
    _ = @import("./cli/commands/runner.zig");
    _ = @import("./cli/commands/watch.zig");
    _ = @import("./cli/version.zig");
    _ = @import("./cli/commands/stats.zig");

    // report module — facade triggers all sub-module tests
    _ = @import("./cli/commands/report.zig");
    // Sub-modules imported explicitly for clarity and direct test discovery
    _ = @import("./cli/commands/report/paths.zig");
    _ = @import("./cli/commands/report/content.zig");
    _ = @import("./cli/commands/report/aggregator.zig");
    _ = @import("./cli/commands/report/writers/markdown.zig");
    _ = @import("./cli/commands/report/writers/json/json_test.zig");
    _ = @import("./cli/commands/report/writers/html/html_test.zig");
    _ = @import("./cli/commands/report/writers/llm.zig");
    _ = @import("./cli/commands/report/writers/sse.zig");

    // _ = @import("./conf/file.zig");
    _ = @import("./conf/file_test.zig");

    _ = @import("./fs/directory_test.zig");
    _ = @import("./fs/watcher.zig");
    _ = @import("./jobs/entry.zig");
    _ = @import("./jobs/process.zig");

    _ = @import("./cli/commands/config/config_test.zig");
    _ = @import("./cli/commands/config/timezone/timezone_test.zig");
}
