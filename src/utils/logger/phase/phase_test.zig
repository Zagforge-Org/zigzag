const phase = @import("./phase.zig");

test "printPhaseStart does not panic" {
    phase.printPhaseStart("Scanning {s}...", .{"./src"});
}

test "printPhaseDone does not panic" {
    phase.printPhaseDone(148_000_000, "{d} files", .{42});
}

test "printPhaseDone no context does not panic" {
    phase.printPhaseDone(1_500_000_000, "", .{});
}
