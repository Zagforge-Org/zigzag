/// Facade — re-exports the runner command implementation.
pub const exec = @import("runner/runner.zig").exec;
pub const BenchResult = @import("runner/runner.zig").BenchResult;
