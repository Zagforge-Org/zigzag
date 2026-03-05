import { L, F, B } from "./state";
import { el, esc } from "./utils";

export function renderLangChart(): void {
    const langEl = document.getElementById("chart-lang")!;
    langEl.innerHTML = "";
    if (L && L.length) {
        const sorted = [...L].sort((a, b) => b.files - a.files);
        const max = sorted[0].files || 1;
        sorted.forEach(function (lg) {
            const row = el("div", "bar-row");
            row.innerHTML =
                '<span class="name">' +
                esc(lg.name) +
                "</span>" +
                '<span class="bar-track"><span class="bar-fill" style="width:' +
                Math.round((lg.files / max) * 100) +
                '%"></span></span>' +
                '<span class="bar-count">' +
                lg.files +
                " file" +
                (lg.files !== 1 ? "s" : "") +
                "</span>";
            langEl.appendChild(row);
        });
    } else {
        langEl.textContent = "No source files.";
    }
}

export function renderSizeChart(): void {
    const buckets: { lbl: string; max: number; count: number }[] = [
        { lbl: "<1 KB", max: 1024, count: 0 },
        { lbl: "1\u201310 KB", max: 10240, count: 0 },
        { lbl: "10\u2013100 KB", max: 102400, count: 0 },
        { lbl: "100 KB\u20131 MB", max: 1048576, count: 0 },
        { lbl: ">1 MB", max: Infinity, count: 0 },
    ];
    [...(F || []), ...(B || [])].forEach(function (f) {
        for (let i = 0; i < buckets.length; i++) {
            if (f.size < buckets[i].max) { buckets[i].count++; break; }
        }
    });
    const sizeEl = document.getElementById("chart-size")!;
    sizeEl.innerHTML = "";
    const histMax = buckets.reduce((m, b) => Math.max(m, b.count), 1);
    const hist = el("div", "hist");
    buckets.forEach(function (b) {
        const col = el("div", "hist-col");
        const h = Math.max(2, Math.round((b.count / histMax) * 90));
        col.innerHTML =
            '<div class="hist-bar" style="height:' +
            h +
            'px" title="' +
            b.count +
            ' files"></div>' +
            '<div class="hist-lbl">' +
            b.lbl +
            "<br><strong>" +
            b.count +
            "</strong></div>";
        hist.appendChild(col);
    });
    sizeEl.appendChild(hist);
}
