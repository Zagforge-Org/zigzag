import type { Report, ReportMeta, ReportSummary, ReportFile, ReportBinary, ReportLanguage } from "./types";

export let R: Report = window.REPORT;
export let M: ReportMeta = R.meta;
export let S: ReportSummary = R.summary;
export let F: ReportFile[] = R.files;
export let B: ReportBinary[] = R.binaries;
export let L: ReportLanguage[] = S.languages;

/** Replace all report state in-place (used by watch-mode soft updates). */
export function setReport(newR: Report): void {
    R = newR;
    M = newR.meta;
    S = newR.summary;
    F = newR.files;
    B = newR.binaries;
    L = S.languages;
    window.REPORT = newR;
}
