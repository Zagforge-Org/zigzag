const print = @import("./print.zig");

test "printStep does not panic" {
    print.printStep("test step {s}", .{"ok"});
}

test "printSuccess does not panic" {
    print.printSuccess("done {d}", .{1});
}

test "printError does not panic" {
    print.printError("failed {s}", .{"reason"});
}

test "printWarn does not panic" {
    print.printWarn("warning {s}", .{"msg"});
}
