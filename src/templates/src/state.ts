import type {
    Report,
    ReportMeta,
    ReportSummary,
    ReportFile,
    ReportBinary,
    ReportLanguage,
} from "./types";

export let _Report: Report = window.REPORT;
export let _ReportMeta: ReportMeta = _Report.meta;
export let _ReportSummary: ReportSummary = _Report.summary;
export let _ReportFile: ReportFile[] = _Report.files;
export let _ReportBinary: ReportBinary[] = _Report.binaries;
export let _ReportLanguage: ReportLanguage[] = _ReportSummary.languages;

/** Replace all report state in-place (used by watch-mode soft updates). */
export function setReport(newReport: Report): void {
    _Report = newReport;
    _ReportMeta = newReport.meta;
    _ReportSummary = newReport.summary;
    _ReportFile = newReport.files;
    _ReportBinary = newReport.binaries;
    _ReportLanguage = _ReportSummary.languages;
    window.REPORT = newReport;
}

/** Recompute summary stats from the current F and B arrays.
 *  Call after mutating F or B via watch-mode deltas so renderCards/charts stay accurate. */
export function recomputeSummary(): void {
    const langMap = new Map<string, ReportLanguage>();
    let totalLines = 0;
    let totalSize = 0;
    for (const f of _ReportFile) {
        totalLines += f.lines;
        totalSize += f.size;
        let l = langMap.get(f.language);
        if (!l) {
            l = { name: f.language, files: 0, lines: 0, size: 0 };
            langMap.set(f.language, l);
        }
        l.files++;
        l.lines += f.lines;
        l.size += f.size;
    }
    for (const b of _ReportBinary) {
        totalSize += b.size;
    }
    _ReportSummary.source_files = _ReportFile.length;
    _ReportSummary.binary_files = _ReportBinary.length;
    _ReportSummary.total_lines = totalLines;
    _ReportSummary.total_size_bytes = totalSize;
    _ReportSummary.languages = Array.from(langMap.values()).sort(
        (a, b) => b.lines - a.lines,
    );
    _ReportLanguage = _ReportSummary.languages;
}
