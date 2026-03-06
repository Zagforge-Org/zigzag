import { M, S } from "./state";
import { el, fmt, fmtNum } from "./utils";

export function renderHeader(): void {
    document.getElementById("report-title")!.textContent = "Code Report: " + M.root_path;
    document.getElementById("report-meta")!.textContent =
        "Generated on " + M.generated_at + " · ZigZag v" + M.version;
}

export function renderCards(): void {
    const defs = [
        { val: fmtNum(S.source_files), lbl: "Source Files" },
        { val: fmtNum(S.total_lines), lbl: "Total Lines" },
        { val: fmtNum(S.binary_files), lbl: "Binary Files" },
        { val: fmt(S.total_size_bytes), lbl: "Total Size" },
    ];
    const cardEl = document.getElementById("cards")!;
    cardEl.innerHTML = "";
    defs.forEach(function (c) {
        const d = el("div", "card");
        d.innerHTML =
            '<div class="val">' + c.val + '</div><div class="lbl">' + c.lbl + "</div>";
        cardEl.appendChild(d);
    });
}
