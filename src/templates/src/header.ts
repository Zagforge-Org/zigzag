import { _ReportMeta, _ReportSummary } from "./state";
import { el, fmt, fmtNum } from "./utils";

export function renderHeader(): void {
    document.getElementById("report-title")!.textContent =
        "Code Report: " + _ReportMeta.root_path;
    document.getElementById("report-meta")!.textContent =
        "Generated on " +
        _ReportMeta.generated_at +
        " · ZigZag v" +
        _ReportMeta.version;
}

export function renderCards(): void {
    const defs = [
        { val: fmtNum(_ReportSummary.source_files), lbl: "Source Files" },
        { val: fmtNum(_ReportSummary.total_lines), lbl: "Total Lines" },
        { val: fmtNum(_ReportSummary.binary_files), lbl: "Binary Files" },
        { val: fmt(_ReportSummary.total_size_bytes), lbl: "Total Size" },
    ];
    const cardEl = document.getElementById("cards")!;
    cardEl.innerHTML = "";
    defs.forEach(function (c) {
        const d = el("div", "card");
        d.innerHTML =
            '<div class="val">' +
            c.val +
            '</div><div class="lbl">' +
            c.lbl +
            "</div>";
        cardEl.appendChild(d);
    });
}
