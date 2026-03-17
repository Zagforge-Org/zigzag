/// Facade — re-exports the public surface of the logger sub-modules.
const fmt_utils = @import("../fmt/fmt.zig");

pub const printSeparator  = @import("./print/print.zig").printSeparator;
pub const printStep       = @import("./print/print.zig").printStep;
pub const printSuccess    = @import("./print/print.zig").printSuccess;
pub const printError      = @import("./print/print.zig").printError;
pub const printWarn       = @import("./print/print.zig").printWarn;

pub const SummaryArgs  = @import("./summary/summary.zig").SummaryArgs;
pub const printSummary = @import("./summary/summary.zig").printSummary;

pub const printPhaseStart   = @import("./phase/phase.zig").printPhaseStart;
pub const printPhaseDone    = @import("./phase/phase.zig").printPhaseDone;
pub const FinalSummaryData  = @import("./phase/phase.zig").FinalSummaryData;
pub const printFinalSummary = @import("./phase/phase.zig").printFinalSummary;

pub const getCpuName = @import("./cpu/cpu.zig").getCpuName;

pub const Logger = @import("./file_logger/file_logger.zig").Logger;

pub const fmtElapsedForTest = fmt_utils.fmtElapsed;
