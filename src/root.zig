//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

test {
    _ = @import("./cli/handlers.zig");
    _ = @import("./cli/commands/config.zig");
    _ = @import("./conf/file.zig");
    _ = @import("./fs/directory_test.zig");
}
