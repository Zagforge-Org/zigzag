//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

/// Re-export the build options so version.zig can detect binary vs runtime mode.
/// Provided by build.zig (real version) or options_fallback.zig (0.0.0 sentinel).
pub const options = @import("options");

const builtin = @import("builtin");

test {
    // handler tests — flags/
    _ = @import("./cli/handlers/flags/chunk_size_test.zig");
    _ = @import("./cli/handlers/flags/html_test.zig");
    _ = @import("./cli/handlers/flags/ignore_test.zig");
    _ = @import("./cli/handlers/flags/json_test.zig");
    _ = @import("./cli/handlers/flags/llm_report_test.zig");
    _ = @import("./cli/handlers/flags/log_test.zig");
    _ = @import("./cli/handlers/flags/mmap_test.zig");
    _ = @import("./cli/handlers/flags/no_watch_test.zig");
    _ = @import("./cli/handlers/flags/open_test.zig");
    _ = @import("./cli/handlers/flags/output_test.zig");
    _ = @import("./cli/handlers/flags/output_dir_test.zig");
    _ = @import("./cli/handlers/flags/path_test.zig");
    _ = @import("./cli/handlers/flags/port_test.zig");
    _ = @import("./cli/handlers/flags/skip_cache_test.zig");
    _ = @import("./cli/handlers/flags/small_test.zig");
    _ = @import("./cli/handlers/flags/timezone_test.zig");
    _ = @import("./cli/handlers/flags/upload_test.zig");
    _ = @import("./cli/handlers/flags/watch_test.zig");
    // handler tests — display/
    _ = @import("./cli/handlers/display/help_test.zig");
    _ = @import("./cli/handlers/display/version_test.zig");
    // handler tests — upload/
    _ = @import("./cli/handlers/upload/upload_test.zig");
    _ = @import("./cli/handlers/upload/git_info_test.zig");
    // handler tests — init/ (previously undiscovered — adds 2 tests)
    _ = @import("./cli/handlers/init/init_test.zig");
    _ = @import("./cli/commands/config/config.zig");
    _ = @import("./cli/commands/runner.zig");

    // runner sub-module tests
    _ = @import("./cli/commands/runner/scan_test.zig");
    _ = @import("./cli/commands/runner/reports_test.zig");

    // watch sub-module tests
    _ = @import("./cli/commands/watch/state_test.zig");
    _ = @import("./cli/commands/watch/server_test.zig");
    _ = @import("./cli/commands/watch/reporter_test.zig");
    _ = @import("./cli/commands/watch/exec_test.zig");
    _ = @import("./cli/version/version_test.zig");
    _ = @import("./cli/commands/stats/stats_test.zig");
    _ = @import("./cli/commands/watch/port_listening_test.zig");

    // report sub-module tests
    _ = @import("./cli/commands/report/aggregator/aggregator_test.zig");
    _ = @import("./cli/commands/report/content/content_test.zig");
    _ = @import("./cli/commands/report/paths/paths_test.zig");
    _ = @import("./cli/commands/report/writers/markdown/markdown_test.zig");
    _ = @import("./cli/commands/report/writers/json/json_test.zig");
    _ = @import("./cli/commands/report/writers/html/html_test.zig");
    _ = @import("./cli/commands/report/writers/llm/llm_test.zig");
    _ = @import("./cli/commands/report/writers/llm/chunk_writer_test.zig");
    _ = @import("./cli/commands/report/writers/sse/sse_test.zig");

    _ = @import("./conf/file_test.zig");
    _ = @import("./cache/impl_test.zig");

    _ = @import("./fs/directory_test.zig");
    _ = @import("./fs/watcher.zig");
    _ = @import("./jobs/entry.zig");
    _ = @import("./jobs/process.zig");

    _ = @import("./cli/commands/serve_test.zig");
    _ = @import("./utils/colors/colors_test.zig");
    _ = @import("./utils/skip_dirs/skip_dirs_test.zig");
    _ = @import("./utils/logger/print/print_test.zig");
    _ = @import("./utils/logger/summary/summary_test.zig");
    _ = @import("./utils/logger/phase/phase_test.zig");
    _ = @import("./utils/logger/cpu/cpu_test.zig");
    _ = @import("./utils/logger/file_logger/file_logger_test.zig");
    _ = @import("./utils/fmt/fmt_test.zig");
    _ = @import("./utils/progress/progress_test.zig");
    _ = @import("./cli/commands/config/config_test.zig");
    _ = @import("./cli/commands/config/timezone/timezone_test.zig");
    _ = @import("./cli/commands/bench/bench_test.zig");

    switch (builtin.os.tag) {
        .linux => {
            _ = @import("./fs/watcher/linux_test.zig");
        },
        .macos, .freebsd, .netbsd, .openbsd, .dragonfly => {
            _ = @import("./fs/watcher/macos_test.zig");
        },
        .windows => {
            _ = @import("./fs/watcher/windows_test.zig");
        },
        else => {},
    }
}
