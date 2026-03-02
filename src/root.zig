//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

test {
    _ = @import("./cli/handlers.zig");
    _ = @import("./cli/commands/config.zig");
    _ = @import("./cli/commands/runner.zig");
    _ = @import("./cli/commands/report.zig");
    _ = @import("./cli/commands/watch.zig");
    _ = @import("./cli/commands/stats.zig");
    _ = @import("./conf/file.zig");
    _ = @import("./fs/directory_test.zig");
    _ = @import("./fs/watcher.zig");
    _ = @import("./jobs/entry.zig");
    _ = @import("./jobs/process.zig");
}
