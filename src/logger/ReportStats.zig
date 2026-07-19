//! ReportStats is pure derivations over FinalSummary timings. No I/O and no
//! styling.

const std = @import("std");
const FinalSummary = @import("FinalSummary.zig");
const Phase = @import("Phase.zig");

pub const phase_count = Phase.all.len;

/// A phase paired with its elapsed time and integer share of the total.
/// `pct == 0` means "under 1%" (the renderer prints it as "<1%").
pub const PhaseTiming = struct {
    phase: Phase,
    ns: u64,
    pct: u64,
};

pub const Totals = struct {
    phases: [phase_count]PhaseTiming,
    total_ns: u64,
};

/// Sum every phase and compute each phase's share of the total.
pub fn totals(data: *const FinalSummary) Totals {
    var total_ns: u64 = 0;
    for (Phase.all) |p| total_ns += Phase.elapsed(p.id, data);

    var phases: [phase_count]PhaseTiming = undefined;
    for (Phase.all, 0..) |p, i| {
        const ns = Phase.elapsed(p.id, data);
        phases[i] = .{
            .phase = p,
            .ns = ns,
            .pct = if (total_ns > 0) ns * 100 / total_ns else 0,
        };
    }
    return .{ .phases = phases, .total_ns = total_ns };
}

/// The three optional "Highlights" bullets. A null field renders nothing,
/// preserving the original conditional output.
pub const Highlights = struct {
    largest: ?Workload,
    markdown_bytes: u64,
    fastest: ?Step,

    pub const Workload = struct { name: []const u8, pct: u64 };
    pub const Step = struct { name: []const u8, ns: u64 };
};

/// Largest and fastest phase by elapsed time. Ties keep the earlier phase, and
/// the largest defaults to "scan" when no phase has run.
pub fn highlights(t: *const Totals, markdown_bytes: u64) Highlights {
    var max_ns: u64 = 0;
    var max_name: []const u8 = "scan";
    var min_ns: u64 = std.math.maxInt(u64);
    var min_name: []const u8 = "";

    for (t.phases) |pt| {
        if (pt.ns > max_ns) {
            max_ns = pt.ns;
            max_name = pt.phase.highlight;
        }
        if (pt.ns > 0 and pt.ns < min_ns) {
            min_ns = pt.ns;
            min_name = pt.phase.highlight;
        }
    }

    return .{
        .largest = if (t.total_ns > 0)
            .{ .name = max_name, .pct = max_ns * 100 / t.total_ns }
        else
            null,
        .markdown_bytes = markdown_bytes,
        .fastest = if (min_name.len > 0)
            .{ .name = min_name, .ns = min_ns }
        else
            null,
    };
}
