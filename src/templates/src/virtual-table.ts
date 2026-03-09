import { esc, fmt, fmtNum } from "./utils";
import { fetchContent, isContentCached } from "./content";
import type { CombinedFile } from "./combined-types";

const ROW_H = 40;   // px — must match tbody tr height in CSS
const OVERSCAN = 10;

export class VirtualTable {
    private files: CombinedFile[] = [];
    private viewport: HTMLElement;
    private tbody: HTMLTableSectionElement;
    private topSpacer: HTMLTableRowElement;
    private botSpacer: HTMLTableRowElement;
    private rafPending = false;
    private onRowClick: (f: CombinedFile) => void;

    constructor(onRowClick: (f: CombinedFile) => void) {
        this.onRowClick = onRowClick;

        // Viewport
        this.viewport = document.createElement("div");
        this.viewport.className = "table-viewport";

        // Table
        const table = document.createElement("table");

        // Sticky header
        const thead = document.createElement("thead");
        thead.innerHTML =
            "<tr><th>Path</th><th>Language</th><th>Lines</th><th>Size</th></tr>";
        table.appendChild(thead);

        // Virtual tbody with top/bottom spacer rows
        this.tbody = document.createElement("tbody");

        this.topSpacer = document.createElement("tr");
        this.topSpacer.style.height = "0";
        const topTd = document.createElement("td");
        topTd.colSpan = 4;
        topTd.style.cssText = "padding:0;border:none;";
        this.topSpacer.appendChild(topTd);

        this.botSpacer = document.createElement("tr");
        this.botSpacer.style.height = "0";
        const botTd = document.createElement("td");
        botTd.colSpan = 4;
        botTd.style.cssText = "padding:0;border:none;";
        this.botSpacer.appendChild(botTd);

        this.tbody.appendChild(this.topSpacer);
        this.tbody.appendChild(this.botSpacer);
        table.appendChild(this.tbody);
        this.viewport.appendChild(table);

        // Scroll → virtual render
        this.viewport.addEventListener("scroll", () => this.scheduleRender());

        // Delegated click
        this.viewport.addEventListener("click", (e) => {
            const span = e.target as HTMLElement;
            if (span.className === "file-link") {
                const idx = parseInt(span.dataset.idx!, 10);
                if (!isNaN(idx) && this.files[idx]) {
                    this.onRowClick(this.files[idx]);
                }
            }
        });

        // Hover prefetch
        this.viewport.addEventListener("mouseover", (e) => {
            const span = e.target as HTMLElement;
            if (span.className !== "file-link") return;
            const idx = parseInt(span.dataset.idx!, 10);
            if (isNaN(idx)) return;
            const f = this.files[idx];
            if (f && !isContentCached(f.root_path + ":" + f.path)) {
                fetchContent(f.root_path + ":" + f.path, function () {});
            }
        });
    }

    /** Replace the displayed file list and re-render from the top. */
    setFiles(files: CombinedFile[]): void {
        this.files = files;
        this.viewport.scrollTop = 0;
        // Synchronous render (not scheduleRender) is required: data-idx in the DOM
        // must always match this.files indices. An async render would leave stale
        // indices from the previous file list clickable until the next rAF fires.
        this.renderVisible();
    }

    /** Return the DOM element to mount into the page. */
    getElement(): HTMLElement {
        return this.viewport;
    }

    /** Scroll the viewport so the file with the given path is visible. */
    scrollToFile(path: string): void {
        const idx = this.files.findIndex((f) => f.path === path);
        if (idx < 0) return;
        this.viewport.scrollTop = Math.max(0, idx - 3) * ROW_H;
        this.renderVisible();
    }

    private scheduleRender(): void {
        if (this.rafPending) return;
        this.rafPending = true;
        requestAnimationFrame(() => {
            this.rafPending = false;
            this.renderVisible();
        });
    }

    private renderVisible(): void {
        const total = this.files.length;
        const scrollTop = this.viewport.scrollTop;
        const viewH = this.viewport.clientHeight;

        const start = Math.max(0, Math.floor(scrollTop / ROW_H) - OVERSCAN);
        const end = Math.min(total, Math.ceil((scrollTop + viewH) / ROW_H) + OVERSCAN);

        this.topSpacer.style.height = start * ROW_H + "px";
        this.botSpacer.style.height = (total - end) * ROW_H + "px";

        // Remove all rows between spacers
        while (this.topSpacer.nextSibling !== this.botSpacer) {
            this.tbody.removeChild(this.topSpacer.nextSibling!);
        }

        const frag = document.createDocumentFragment();
        for (let i = start; i < end; i++) {
            const f = this.files[i];
            const tr = document.createElement("tr");
            tr.style.height = ROW_H + "px";
            tr.innerHTML =
                '<td><span class="file-link" data-idx="' + i + '">' + esc(f.path) + "</span></td>" +
                '<td><span class="tag">' + esc(f.language || "\u2014") + "</span></td>" +
                "<td><span>" + fmtNum(f.lines) + "</span></td>" +
                "<td><span>" + fmt(f.size) + "</span></td>";
            frag.appendChild(tr);
        }
        this.tbody.insertBefore(frag, this.botSpacer);
    }
}
