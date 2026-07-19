//! FinalSummary: timing and volume totals for one full report run.

total_ns: u64,
scan_ns: u64,
aggregate_ns: u64,
write_md_ns: u64,
write_json_ns: u64,
write_html_ns: u64,
write_llm_ns: u64,
files_total: usize,
md_bytes: u64,
path_names: []const []const u8,
has_combined: bool,
