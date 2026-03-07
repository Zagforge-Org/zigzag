import { fetchContent, updateContentEntry } from "./content";
import { openViewer } from "./viewer";
import { esc, fmt } from "./utils";
import type { CombinedFile, CombinedPathReport } from "./combined-types";

const R = window.COMBINED_REPORT;
const M = R.meta;
const S = R.summary;

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
        .map((c) => `<div class="card"><div class="card-value">${esc(c.value)}</div><div class="card-label">${esc(c.label)}</div></div>`)
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

function filterAllSections(q: string): void {
    document.querySelectorAll<HTMLElement>(".path-section").forEach((section) => {
        const rootPath = section.dataset.rootPath!;
        const pathData = R.paths.find((p) => p.root_path === rootPath)!;
        const tbody = section.querySelector<HTMLElement>(".file-tbody")!;
        const count = section.querySelector<HTMLElement>(".path-file-count")!;
        const visible = pathData.files.filter((f) => matchesSearch(f, q));
        count.textContent = visible.length + " / " + pathData.files.length + " files";
        tbody.innerHTML = visible
            .map((f) => renderFileRow(f))
            .join("");
        attachRowListeners(tbody);
    });
}

// ── File rows ─────────────────────────────────────────────────────────────────

function renderFileRow(f: CombinedFile): string {
    return `<tr class="file-row" data-path="${esc(f.path)}" data-root="${esc(f.root_path)}">
        <td>${esc(f.path)}</td>
        <td>${esc(f.language)}</td>
        <td>${f.lines.toLocaleString()}</td>
        <td>${fmt(f.size)}</td>
    </tr>`;
}

function attachRowListeners(tbody: HTMLElement): void {
    tbody.querySelectorAll<HTMLElement>(".file-row").forEach((row) => {
        row.addEventListener("click", () => {
            const filePath = row.dataset.path!;
            const rootPath = row.dataset.root!;
            const pathData = R.paths.find((p) => p.root_path === rootPath)!;
            const file = pathData.files.find((f) => f.path === filePath)!;
            openCombinedViewer(file);
        });
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

    const fileRows = p.files.map((f) => renderFileRow(f)).join("");

    return `
<div class="path-section${expanded ? " expanded" : ""}" data-root-path="${esc(p.root_path)}">
    <div class="path-header" role="button" tabindex="0">
        <span class="path-toggle">${expanded ? "▾" : "▸"}</span>
        <span class="path-name">${esc(p.root_path)}</span>
        <span class="path-stats">${esc(p.summary.source_files)} files · ${esc(p.summary.total_lines.toLocaleString())} lines · ${esc(fmt(p.summary.total_size_bytes))}</span>
    </div>
    <div class="path-body" style="${expanded ? "" : "display:none"}">
        <div class="path-summary-row">
            <div class="card"><div class="card-value">${esc(p.summary.source_files)}</div><div class="card-label">Source Files</div></div>
            <div class="card"><div class="card-value">${esc(p.summary.binary_files)}</div><div class="card-label">Binary Files</div></div>
            <div class="card"><div class="card-value">${esc(p.summary.total_lines.toLocaleString())}</div><div class="card-label">Total Lines</div></div>
            <div class="card"><div class="card-value">${esc(fmt(p.summary.total_size_bytes))}</div><div class="card-label">Total Size</div></div>
        </div>
        ${langRows ? `
        <table class="lang-table">
            <thead><tr><th>Language</th><th>Files</th><th>Lines</th><th>Size</th></tr></thead>
            <tbody>${langRows}</tbody>
        </table>` : ""}
        <p class="path-file-count">${p.files.length} files</p>
        <table class="file-table">
            <thead><tr><th>Path</th><th>Language</th><th>Lines</th><th>Size</th></tr></thead>
            <tbody class="file-tbody">${fileRows}</tbody>
        </table>
    </div>
</div>`;
}

function attachSectionToggle(section: HTMLElement): void {
    const header = section.querySelector<HTMLElement>(".path-header")!;
    header.addEventListener("click", () => {
        const expanded = section.classList.toggle("expanded");
        const toggle = section.querySelector<HTMLElement>(".path-toggle")!;
        const body = section.querySelector<HTMLElement>(".path-body")!;
        toggle.textContent = expanded ? "▾" : "▸";
        body.style.display = expanded ? "" : "none";
    });
    header.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") { e.preventDefault(); header.click(); }
    });
}

// ── Render all path sections ──────────────────────────────────────────────────

function renderPathSections(): void {
    const container = document.getElementById("path-sections")!;
    container.innerHTML = R.paths.map((p, i) => renderPathSection(p, i)).join("");
    container.querySelectorAll<HTMLElement>(".path-section").forEach((section) => {
        attachSectionToggle(section);
        attachRowListeners(section.querySelector<HTMLElement>(".file-tbody")!);
    });
}

// ── Search bar ────────────────────────────────────────────────────────────────

const searchEl = document.getElementById("search") as HTMLInputElement | null;
if (searchEl) {
    searchEl.addEventListener("input", () => filterAllSections(searchEl.value.trim()));
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
