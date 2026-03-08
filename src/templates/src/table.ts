import { F } from "./state";
import { el, esc, fmt, fmtNum } from "./utils";
import { isContentCached, fetchContent } from "./content";
import { openViewer } from "./viewer";
import type { ReportFile } from "./types";

// ── Table state ───────────────────────────────────────────────────────────────

const ROW_H = 40;
const OVERSCAN = 10;
const COLS = ["path", "lines", "size", "language"];

let sortCol = "path";
let sortAsc = true;
let tableFiles: ReportFile[] = [];
let tableViewport: HTMLElement | null = null;
let tableTopSpacer: HTMLElement | null = null;
let tableBottomSpacer: HTMLElement | null = null;
let tableTbody: HTMLElement | null = null;
let rafPending = false;

// ── DOM construction ──────────────────────────────────────────────────────────

export function buildTableDOM(): HTMLElement {
    tableViewport = el("div", "table-viewport");
    const table = el("table");

    // Sticky header
    const hdr = el("thead");
    const hdrRow = el("tr");
    COLS.forEach(function (c) {
        const th = el("th");
        const arrow = c === sortCol ? (sortAsc ? "&#x2191;" : "&#x2193;") : "&#x2195;";
        if (c === sortCol) th.className = "sorted";
        th.dataset.col = c;
        th.innerHTML =
            c.charAt(0).toUpperCase() + c.slice(1) + '<span class="sort-icon">' + arrow + "</span>";
        hdrRow.appendChild(th);
    });
    hdr.appendChild(hdrRow);
    table.appendChild(hdr);

    // Virtual body with spacer rows
    tableTbody = el("tbody");
    tableTopSpacer = el("tr");
    tableTopSpacer.style.height = "0";
    tableBottomSpacer = el("tr");
    tableBottomSpacer.style.height = "0";
    const topTd = document.createElement("td");
    topTd.colSpan = 4;
    topTd.style.cssText = "padding:0;border:none;";
    const botTd = document.createElement("td");
    botTd.colSpan = 4;
    botTd.style.cssText = "padding:0;border:none;";
    tableTopSpacer.appendChild(topTd);
    tableBottomSpacer.appendChild(botTd);
    tableTbody.appendChild(tableTopSpacer);
    tableTbody.appendChild(tableBottomSpacer);
    table.appendChild(tableTbody);
    tableViewport.appendChild(table);

    // Delegated header sort
    hdr.addEventListener("click", function (e) {
        const th = (e.target as HTMLElement).closest?.("th[data-col]") as HTMLElement | null;
        if (!th) return;
        const c = th.dataset.col!;
        if (sortCol === c) sortAsc = !sortAsc;
        else { sortCol = c; sortAsc = true; }
        renderTable();
    });

    // Delegated row open
    tableViewport.addEventListener("click", function (e) {
        const span = e.target as HTMLElement;
        if (span.className === "file-link") {
            openViewer(tableFiles[parseInt(span.dataset.idx!, 10)]);
        }
    });

    // Hover prefetch
    tableViewport.addEventListener("mouseover", function (e) {
        const span = e.target as HTMLElement;
        if (span.className !== "file-link") return;
        const idx = parseInt(span.dataset.idx!, 10);
        if (isNaN(idx)) return;
        const f = tableFiles[idx];
        if (f && !isContentCached(f.path)) {
            fetchContent(f.path, function () {});
        }
    });

    // Virtual scroll
    tableViewport.addEventListener("scroll", scheduleVirtualRender);

    return tableViewport;
}

// ── Virtual rendering ─────────────────────────────────────────────────────────

function scheduleVirtualRender(): void {
    if (rafPending) return;
    rafPending = true;
    requestAnimationFrame(function () {
        rafPending = false;
        renderVisibleRows();
    });
}

function renderVisibleRows(): void {
    const total = tableFiles.length;
    const scrollTop = tableViewport!.scrollTop;
    const viewH = tableViewport!.clientHeight;

    const start = Math.max(0, Math.floor(scrollTop / ROW_H) - OVERSCAN);
    const end = Math.min(total, Math.ceil((scrollTop + viewH) / ROW_H) + OVERSCAN);

    tableTopSpacer!.style.height = start * ROW_H + "px";
    tableBottomSpacer!.style.height = (total - end) * ROW_H + "px";

    while (tableTopSpacer!.nextSibling !== tableBottomSpacer) {
        tableTbody!.removeChild(tableTopSpacer!.nextSibling!);
    }

    const frag = document.createDocumentFragment();
    for (let i = start; i < end; i++) {
        const f = tableFiles[i];
        const tr = document.createElement("tr");
        tr.style.height = ROW_H + "px";
        tr.innerHTML =
            '<td><span class="file-link" data-idx="' + i + '">' + esc(f.path) + "</span></td>" +
            "<td><span>" + fmtNum(f.lines) + "</span></td>" +
            "<td><span>" + fmt(f.size) + "</span></td>" +
            '<td><span class="tag">' + esc(f.language || "\u2014") + "</span></td>";
        frag.appendChild(tr);
    }
    tableTbody!.insertBefore(frag, tableBottomSpacer);
}

function updateHeaderSortIndicators(): void {
    if (!tableViewport) return;
    tableViewport.querySelectorAll<HTMLElement>("th[data-col]").forEach(function (th) {
        const c = th.dataset.col!;
        th.className = c === sortCol ? "sorted" : "";
        const arrow = c === sortCol ? (sortAsc ? "&#x2191;" : "&#x2193;") : "&#x2195;";
        th.innerHTML =
            c.charAt(0).toUpperCase() + c.slice(1) + '<span class="sort-icon">' + arrow + "</span>";
    });
}

// ── Public API ────────────────────────────────────────────────────────────────

const search = document.getElementById("search") as HTMLInputElement;

export function renderTable(): number {
    const query = (search.value || "").toLowerCase();
    tableFiles = (F || []).filter(function (f) {
        return !query || f.path.toLowerCase().indexOf(query) >= 0;
    });
    tableFiles.sort(function (a, b) {
        const av = a[sortCol as keyof ReportFile];
        const bv = b[sortCol as keyof ReportFile];
        if (typeof av === "number") return sortAsc ? (av - (bv as number)) : ((bv as number) - av);
        return sortAsc
            ? String(av).localeCompare(String(bv))
            : String(bv).localeCompare(String(av));
    });
    updateHeaderSortIndicators();
    tableViewport!.scrollTop = 0;
    renderVisibleRows();
    return tableFiles.length;
}

export function getTotalCount(): number { return F.length; }

