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
    _ = @import("./cli/commands/config/config.zig");
    _ = @import("./cli/commands/runner.zig");

    // watch sub-module tests
    _ = @import("./cli/commands/watch/state_test.zig");
    _ = @import("./cli/commands/watch/server_test.zig");
    _ = @import("./cli/commands/watch/reporter_test.zig");
    _ = @import("./cli/commands/watch/exec_test.zig");
    _ = @import("./cli/version/version_test.zig");
    _ = @import("./cli/commands/stats/stats_test.zig");

    // report sub-module tests
    _ = @import("./cli/commands/report/aggregator/aggregator_test.zig");
    _ = @import("./cli/commands/report/content/content_test.zig");
    _ = @import("./cli/commands/report/paths/paths_test.zig");
    _ = @import("./cli/commands/report/writers/markdown/markdown_test.zig");
    _ = @import("./cli/commands/report/writers/json/json_test.zig");
    _ = @import("./cli/commands/report/writers/html/html_test.zig");
    _ = @import("./cli/commands/report/writers/llm/llm_test.zig");
    _ = @import("./cli/commands/report/writers/sse/sse_test.zig");

    _ = @import("./conf/file_test.zig");

    _ = @import("./fs/directory_test.zig");
    _ = @import("./fs/watcher.zig");
    _ = @import("./jobs/entry.zig");
    _ = @import("./jobs/process.zig");

    _ = @import("./cli/commands/config/config_test.zig");
    _ = @import("./cli/commands/config/timezone/timezone_test.zig");

    _ = @import("./fs/watcher/linux_test.zig");
}
