const std = @import("std");
const bench = @import("../bench.zig");

test "printTable does not panic with populated BenchResult" {
    var result = bench.BenchResult{
        .scan_ns = 340_000_000,
        .aggregate_ns = 12_000_000,
        .write_md_ns = 8_000_000,
        .write_json_ns = 60_000_000,
        .write_html_ns = 45_000_000,
        .write_llm_ns = 0,
        .files_total = 1423,
        .files_source = 1350,
        .files_binary = 50,
        .files_ignored = 23,
        .md_bytes = 46_080,
        .json_bytes = 122_880,
        .html_bytes = 2_202_009,
        .llm_bytes = 0,
    };
    bench.printTable(&result);
}

test "printTable with all-zero BenchResult does not panic" {
    var result: bench.BenchResult = .{};
    bench.printTable(&result);
}
