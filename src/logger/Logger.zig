//! Centralized logger facade: re-exports the public surface of the three logger
//! concerns.

const file_mod = @import("file.zig");
pub const initFile = file_mod.initFile;
pub const deinitFile = file_mod.deinitFile;
pub const fileEnabled = file_mod.fileEnabled;
pub const file = file_mod.file;

const ConsoleWriter = @import("ConsoleWriter.zig");
pub const setTestSink = ConsoleWriter.setTestSink;

const console_mod = @import("console.zig");
pub const separator = console_mod.separator;
pub const step = console_mod.step;
pub const success = console_mod.success;
pub const err = console_mod.err;
pub const warn = console_mod.warn;
pub const phaseStart = console_mod.phaseStart;
pub const phaseDone = console_mod.phaseDone;

const summary_mod = @import("Summary.zig");
pub const Summary = summary_mod;
pub const summary = summary_mod.summary;

const report_mod = @import("report.zig");
pub const FinalSummary = report_mod.FinalSummary;
pub const finalSummary = report_mod.finalSummary;
