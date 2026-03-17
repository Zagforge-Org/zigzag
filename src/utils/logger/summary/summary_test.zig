const summary = @import("./summary.zig");

test "printSummary does not panic" {
    summary.printSummary(.{
        .path = "./src",
        .total = 10,
        .source = 8,
        .cached = 5,
        .fresh = 3,
        .binary = 1,
        .ignored = 1,
    });
}
