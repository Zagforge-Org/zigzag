import { fetchContent, updateContentEntry, setContentPrefix } from "./content";
setContentPrefix("combined-content");
import { openViewer } from "./viewer";
import { esc, fmt } from "./utils";
import type { CombinedFile, CombinedPathReport } from "./combined-types";
import { initTheme, toggleTheme } from "./theme";
import { VirtualTable } from "./virtual-table";

const R = window.COMBINED_REPORT;
const M = R.meta;
const S = R.summary;

const sectionTables = new Map<string, VirtualTable>();

// Theme must run before any rendering
initTheme();
const themeBtn = document.getElementById("theme-toggle");
if (themeBtn) themeBtn.addEventListener("click", toggleTheme);

// ── Global summary cards ───────────────────────────────────────────────────────

function renderGlobalSummary(): void {
    const cards = document.getElementById("cards")!;
    const items = [
        { label: "Paths",        value: String(M.path_count) },
        { label: "Source Files", value: String(S.source_files) },
        { label: "Binary Files", value: String(S.binary_files) },
        { label: "Total Lines",  value: S.total_lines.toLocaleString() },
        { label: "Total Size",   value: fmt(S.total_size_bytes) },
    ];
    cards.innerHTML = items
        .map((c) => `<div class="card"><div class="val">${esc(c.value)}</div><div class="lbl">${esc(c.label)}</div></div>`)
        .join("");
}

// ── Search ─────────────────────────────────────────────────────────────────────

function matchesSearch(f: CombinedFile, q: string): boolean {
    if (!q) return true;
    const lower = q.toLowerCase();
    return (
        f.path.toLowerCase().includes(lower) ||
        f.root_path.toLowerCase().includes(lower) ||
        f.language.toLowerCase().includes(lower)
    );
}

function currentFilteredFiles(pathData: CombinedPathReport): CombinedFile[] {
    const q = searchEl ? searchEl.value.trim().toLowerCase() : "";
    return q ? pathData.files.filter((f) => matchesSearch(f, q)) : pathData.files;
}

function filterAllSections(q: string): void {
    document.querySelectorAll<HTMLElement>(".path-section").forEach((section) => {
        const rootPath = section.dataset.rootPath!;
        const pathData = R.paths.find((p) => p.root_path === rootPath)!;
        const count = section.querySelector<HTMLElement>(".path-file-count")!;
        const visible = pathData.files.filter((f) => matchesSearch(f, q));
        count.textContent = visible.length + " / " + pathData.files.length + " files";
        const vtable = sectionTables.get(rootPath);
        if (vtable) vtable.setFiles(visible);
    });
}

// ── Source viewer bridge ──────────────────────────────────────────────────────
// Content sidecar keys are "{root_path}:{path}". viewer.ts looks up by file.path.
// Bridge: fetch with combined key, alias into cache under plain path, then open.

function openCombinedViewer(file: CombinedFile): void {
    const contentKey = file.root_path + ":" + file.path;
    fetchContent(contentKey, (src: string) => {
        updateContentEntry(file.path, src);
        openViewer({ path: file.path, size: file.size, lines: file.lines, language: file.language });
    });
}

// ── Per-path sections ─────────────────────────────────────────────────────────

function renderPathSection(p: CombinedPathReport, index: number): string {
    const expanded = index === 0;
    const langRows = p.summary.languages
        .slice(0, 5)
        .map((l) => `<tr><td>${esc(l.name)}</td><td>${l.files}</td><td>${l.lines.toLocaleString()}</td><td>${fmt(l.size_bytes)}</td></tr>`)
        .join("");

    return `
<div class="path-section${expanded ? " expanded" : ""}" data-root-path="${esc(p.root_path)}">
    <div class="path-header" role="button" tabindex="0">
        <span class="path-toggle">&#9658;</span>
        <span class="path-name">${esc(p.root_path)}</span>
        <span class="path-stats">${p.summary.source_files} files · ${p.summary.total_lines.toLocaleString()} lines · ${fmt(p.summary.total_size_bytes)}</span>
    </div>
    <div class="path-body">
        <div class="path-body-inner">
            <div class="path-summary-row">
                <div class="card"><div class="val">${esc(String(p.summary.source_files))}</div><div class="lbl">Source Files</div></div>
                <div class="card"><div class="val">${esc(String(p.summary.binary_files))}</div><div class="lbl">Binary Files</div></div>
                <div class="card"><div class="val">${esc(p.summary.total_lines.toLocaleString())}</div><div class="lbl">Total Lines</div></div>
                <div class="card"><div class="val">${esc(fmt(p.summary.total_size_bytes))}</div><div class="lbl">Total Size</div></div>
            </div>
            ${langRows ? `
            <table class="lang-table">
                <thead><tr><th>Language</th><th>Files</th><th>Lines</th><th>Size</th></tr></thead>
                <tbody>${langRows}</tbody>
            </table>` : ""}
            <input class="section-search" type="text" placeholder="Filter files\u2026" data-root="${esc(p.root_path)}">
            <p class="path-file-count" data-root="${esc(p.root_path)}">${p.files.length} files</p>
            <div class="vtable-mount"></div>
        </div>
    </div>
</div>`;
}

function attachSectionToggle(section: HTMLElement, pathData: CombinedPathReport): void {
    const header = section.querySelector<HTMLElement>(".path-header")!;
    const mount = section.querySelector<HTMLElement>(".vtable-mount")!;
    const rootPath = pathData.root_path;

    function maybeMount(): void {
        if (!section.classList.contains("expanded")) return;
        if (sectionTables.has(rootPath)) return;
        const vtable = new VirtualTable(openCombinedViewer);
        mount.appendChild(vtable.getElement());
        vtable.setFiles(currentFilteredFiles(pathData));
        sectionTables.set(rootPath, vtable);
    }

    header.addEventListener("click", () => {
        section.classList.toggle("expanded");
        maybeMount();
    });
    header.addEventListener("keydown", (e: KeyboardEvent) => {
        if (e.key === "Enter" || e.key === " ") { e.preventDefault(); header.click(); }
    });

    // First section starts expanded — mount immediately
    if (section.classList.contains("expanded")) {
        maybeMount();
    }
}

function attachSectionSearch(section: HTMLElement, pathData: CombinedPathReport): void {
    const input = section.querySelector<HTMLInputElement>(".section-search");
    if (!input) return;
    const countEl = section.querySelector<HTMLElement>(".path-file-count")!;
    input.addEventListener("input", function () {
        const q = input.value.trim().toLowerCase();
        const visible = q
            ? pathData.files.filter((f) => f.path.toLowerCase().includes(q) || f.language.toLowerCase().includes(q))
            : pathData.files;
        const vtable = sectionTables.get(pathData.root_path);
        if (vtable) vtable.setFiles(visible);
        countEl.textContent = visible.length + " / " + pathData.files.length + " files";
    });
}

// ── Render all path sections ──────────────────────────────────────────────────

function renderPathSections(): void {
    const container = document.getElementById("path-sections")!;
    container.innerHTML = R.paths.map((p, i) => renderPathSection(p, i)).join("");
    container.querySelectorAll<HTMLElement>(".path-section").forEach((section, i) => {
        attachSectionToggle(section, R.paths[i]);
        attachSectionSearch(section, R.paths[i]);
    });
}

// ── Header ────────────────────────────────────────────────────────────────────

document.getElementById("report-title")!.textContent =
    "Code Report: " + M.path_count + " paths";
document.getElementById("report-meta")!.textContent =
    "Generated on " + M.generated_at + " · ZigZag v" + M.version +
    (M.failed_paths > 0 ? ` · \u26a0 ${M.failed_paths} path(s) failed` : "");

// ── Init ──────────────────────────────────────────────────────────────────────

renderGlobalSummary();
renderPathSections();

// ── Search bar ────────────────────────────────────────────────────────────────

const searchEl = document.getElementById("search") as HTMLInputElement | null;
const clearBtn = document.getElementById("search-clear") as HTMLButtonElement | null;
const countEl  = document.getElementById("search-count") as HTMLElement | null;

function updateSearchCount(q: string): void {
    if (!countEl) return;
    const total = R.paths.reduce((s, p) => s + p.files.length, 0);
    if (!q) {
        countEl.textContent = `${total} files`;
    } else {
        let matched = 0;
        R.paths.forEach((p) => {
            matched += p.files.filter((f) => matchesSearch(f, q)).length;
        });
        countEl.textContent = `${matched} / ${total} files`;
    }
}

if (searchEl) {
    searchEl.addEventListener("input", () => {
        const q = searchEl.value.trim();
        filterAllSections(q);
        if (clearBtn) clearBtn.classList.toggle("visible", q.length > 0);
        updateSearchCount(q);
    });
}
if (clearBtn) {
    clearBtn.addEventListener("click", () => {
        if (searchEl) { searchEl.value = ""; filterAllSections(""); updateSearchCount(""); }
        clearBtn.classList.remove("visible");
    });
}
// Initial count
updateSearchCount("");

// ── Watch mode SSE ────────────────────────────────────────────────────────────

if (M.watch_mode && M.sse_url) {
    const dot = document.getElementById("sse-dot") as HTMLElement | null;
    function setDot(state: "live" | "reconnecting"): void {
        if (!dot) return;
        dot.style.display = "block";
        dot.classList.toggle("reconnecting", state === "reconnecting");
        dot.title = state === "live" ? "Watch: live" : "Watch: reconnecting…";
    }
    try {
        const es = new EventSource(M.sse_url);
        es.onopen = () => setDot("live");
        es.onerror = () => setDot("reconnecting");
        es.addEventListener("reload", () => { location.reload(); });
    } catch { /* SSE unavailable */ }
}
