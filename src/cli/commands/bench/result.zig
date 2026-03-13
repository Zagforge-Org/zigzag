/// Per-phase timing and context stats collected during a benchmarked run.
/// All ns fields accumulate across multiple paths with +=.
pub const BenchResult = struct {
    scan_ns: u64 = 0,
    aggregate_ns: u64 = 0,
    write_md_ns: u64 = 0,
    write_json_ns: u64 = 0,
    write_html_ns: u64 = 0,
    write_llm_ns: u64 = 0,

    files_total: usize = 0,
    files_source: usize = 0,
    files_binary: usize = 0,
    files_ignored: usize = 0,
    md_bytes: u64 = 0,
    json_bytes: u64 = 0,
    html_bytes: u64 = 0,
    llm_bytes: u64 = 0,
};
