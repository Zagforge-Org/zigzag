# Dashboard Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Redesign both dashboards (single-path + combined) with a Shadcn base + Aceternity accents design system, add a persistent light/dark theme switcher, fix watch-mode auto-refresh on the combined dashboard, and improve search clarity.

**Architecture:** All theming lives in CSS custom properties switched by `data-theme` on `<html>`. A new `theme.ts` module handles detection and persistence. The combined dashboard gets its own minimal SSE watcher for `reload` events. Both HTML templates get a shared header pattern (accent bar, gradient title, theme toggle, status dot).

**Tech Stack:** Zig 0.15.2, TypeScript, esbuild (via bundle.py), CSS custom properties, EventSource SSE.

**Design reference:** `docs/plans/2026-03-07-dashboard-redesign-design.md`

---

## Task 1: Rewrite dashboard.css with the new design system

**Files:**
- Rewrite: `src/templates/src/dashboard.css`

**What to do:** Complete replacement. The old file uses hardcoded GitHub-dark colors and a `@media` query for dark mode. The new file uses `[data-theme]` attribute switching, the approved token set, and all new component styles. Paste the entire block below, replacing the file contents.

**New file content:**

```css
/* ── Reset ─────────────────────────────────────────────────────────── */
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

/* ── Design tokens — light (default) ───────────────────────────────── */
:root,
[data-theme="light"] {
    --bg:            #fafafa;
    --bg-card:       #ffffff;
    --bg-card-hover: #f4f4f5;
    --border:        #e4e4e7;
    --border-hover:  #d4d4d8;
    --text:          #09090b;
    --text-muted:    #71717a;
    --text-subtle:   #d4d4d8;
    --accent:        #4f46e5;
    --accent-rgb:    79,70,229;
    --accent-glow:   rgba(79,70,229,0.08);
    --radius:        0.625rem;
}

/* ── Design tokens — dark ───────────────────────────────────────────── */
[data-theme="dark"] {
    --bg:            #111113;
    --bg-card:       #1c1c20;
    --bg-card-hover: #232329;
    --border:        #2e2e33;
    --border-hover:  #3f3f46;
    --text:          #fafafa;
    --text-muted:    #a1a1aa;
    --text-subtle:   #52525b;
    --accent:        #6366f1;
    --accent-rgb:    99,102,241;
    --accent-glow:   rgba(99,102,241,0.12);
    --radius:        0.625rem;
}

/* ── Base ───────────────────────────────────────────────────────────── */
body {
    font-family: system-ui, -apple-system, 'Segoe UI', sans-serif;
    background: var(--bg);
    color: var(--text);
    line-height: 1.5;
    font-size: 0.9375rem;
}

/* ── Accent bar (top of header) ─────────────────────────────────────── */
@keyframes zz-gradient-slide {
    0%   { background-position: 0% 50%; }
    50%  { background-position: 100% 50%; }
    100% { background-position: 0% 50%; }
}
.accent-bar {
    height: 3px;
    background: linear-gradient(90deg, #6366f1, #8b5cf6, #a78bfa, #6366f1);
    background-size: 200% 200%;
    animation: zz-gradient-slide 6s ease infinite;
}

/* ── Header ─────────────────────────────────────────────────────────── */
header {
    background: var(--bg-card);
    border-bottom: 1px solid var(--border);
    padding: 1rem 1.5rem;
    display: flex;
    align-items: center;
    gap: 1rem;
}
.header-left {
    flex: 1;
    min-width: 0;
}
.wordmark {
    font-size: 0.7rem;
    font-variant: small-caps;
    letter-spacing: 0.1em;
    color: var(--text-subtle);
    margin-bottom: 0.2rem;
}
#report-title {
    font-size: 1.25rem;
    font-weight: 700;
    background: linear-gradient(to right, var(--text), var(--text-muted));
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    background-clip: text;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}
#report-meta {
    font-size: 0.78rem;
    color: var(--text-muted);
    margin-top: 0.15rem;
}
.header-right {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    flex-shrink: 0;
}

/* SSE status dot */
#sse-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: #22c55e;
    flex-shrink: 0;
    display: none; /* shown via JS when watch_mode=true */
}
#sse-dot.reconnecting { background: #f59e0b; }

/* Theme toggle */
#theme-toggle {
    width: 36px;
    height: 36px;
    border-radius: 50%;
    border: 1px solid var(--border);
    background: var(--bg-card);
    color: var(--text-muted);
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: border-color 150ms, color 150ms;
    flex-shrink: 0;
}
#theme-toggle:hover {
    border-color: var(--border-hover);
    color: var(--text);
}
#theme-toggle svg { width: 16px; height: 16px; pointer-events: none; }
.icon-sun, .icon-moon { transition: opacity 200ms; }
[data-theme="dark"]  .icon-sun  { display: none; }
[data-theme="light"] .icon-moon { display: none; }

/* ── Page container ─────────────────────────────────────────────────── */
.container {
    max-width: 1200px;
    margin: 0 auto;
    padding: 1.5rem 1.5rem;
}

/* ── Section heading ─────────────────────────────────────────────────── */
h2 {
    font-size: 0.7rem;
    font-weight: 600;
    color: var(--text-muted);
    text-transform: uppercase;
    letter-spacing: 0.08em;
    margin-bottom: 0.875rem;
}

/* ── Stat cards ─────────────────────────────────────────────────────── */
.cards {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
    gap: 0.875rem;
    margin-bottom: 1.5rem;
}
.card {
    background: var(--bg-card);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 1.25rem 1rem;
    text-align: center;
    transition: transform 150ms ease, box-shadow 150ms ease, border-color 150ms ease;
    cursor: default;
}
.card:hover {
    transform: translateY(-2px);
    box-shadow: 0 0 0 1px var(--border-hover), 0 4px 16px var(--accent-glow);
    border-color: var(--border-hover);
}
.card .val {
    font-size: 1.75rem;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    color: var(--text);
    line-height: 1.1;
}
.card .lbl {
    font-size: 0.7rem;
    color: var(--text-muted);
    text-transform: uppercase;
    letter-spacing: 0.08em;
    margin-top: 0.35rem;
}

/* ── Section wrapper ─────────────────────────────────────────────────── */
.section {
    background: var(--bg-card);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 1.25rem 1.5rem;
    margin-bottom: 1.25rem;
}

/* ── Language bar chart ──────────────────────────────────────────────── */
.bar-row {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    margin-bottom: 0.5rem;
    font-size: 0.85rem;
}
.bar-row .name {
    width: 90px;
    text-align: right;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    color: var(--text-muted);
}
.bar-track {
    flex: 1;
    background: var(--border);
    border-radius: 3px;
    height: 16px;
    overflow: hidden;
}
.bar-fill {
    height: 100%;
    background: var(--accent);
    border-radius: 3px;
    transition: width 0.3s;
}
.bar-count {
    min-width: 36px;
    color: var(--text-muted);
    font-size: 0.78rem;
    font-variant-numeric: tabular-nums;
}

/* ── Size histogram ──────────────────────────────────────────────────── */
.hist {
    display: flex;
    align-items: flex-end;
    gap: 4px;
    height: 100px;
}
.hist-col {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 4px;
}
.hist-bar {
    width: 100%;
    background: var(--accent);
    border-radius: 3px 3px 0 0;
    min-height: 2px;
    opacity: 0.8;
}
.hist-lbl {
    font-size: 0.62rem;
    color: var(--text-muted);
    text-align: center;
    line-height: 1.2;
}

/* ── Search bar ─────────────────────────────────────────────────────── */
.search-wrap {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    background: var(--bg-card);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 0 0.75rem;
    margin-bottom: 1rem;
    transition: border-color 150ms, box-shadow 150ms;
}
.search-wrap:focus-within {
    border-color: var(--accent);
    box-shadow: 0 0 0 3px rgba(var(--accent-rgb), 0.15);
}
.search-icon { color: var(--text-subtle); flex-shrink: 0; }
.search-wrap input {
    flex: 1;
    border: none;
    background: transparent;
    color: var(--text);
    font-size: 0.875rem;
    padding: 0.625rem 0;
    outline: none;
}
.search-wrap input::placeholder { color: var(--text-subtle); }
.search-clear {
    background: none;
    border: none;
    color: var(--text-subtle);
    cursor: pointer;
    font-size: 1rem;
    padding: 0.125rem 0.25rem;
    line-height: 1;
    display: none;
}
.search-clear.visible { display: block; }
.search-count {
    font-size: 0.75rem;
    color: var(--text-muted);
    white-space: nowrap;
    font-variant-numeric: tabular-nums;
    background: var(--bg);
    border: 1px solid var(--border);
    border-radius: 999px;
    padding: 0.125rem 0.5rem;
}

/* ── File table ─────────────────────────────────────────────────────── */
.table-viewport {
    height: 480px;
    overflow-y: auto;
    border: 1px solid var(--border);
    border-radius: var(--radius);
}
table {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.85rem;
}
thead {
    position: sticky;
    top: 0;
    z-index: 1;
    background: var(--bg-card);
}
thead th {
    padding: 0.6rem 0.875rem;
    text-align: left;
    font-size: 0.7rem;
    font-weight: 600;
    color: var(--text-muted);
    text-transform: uppercase;
    letter-spacing: 0.06em;
    border-bottom: 1px solid var(--border);
    white-space: nowrap;
}
tbody td {
    padding: 0.55rem 0.875rem;
    border-bottom: 1px solid var(--border);
    vertical-align: middle;
}
tbody tr:last-child td { border-bottom: none; }
tbody tr { transition: background 80ms; cursor: pointer; }
tbody tr:hover td { background: var(--bg-card-hover); }
td.path-cell {
    font-family: ui-monospace, 'Cascadia Code', 'Fira Code', monospace;
    font-size: 0.8rem;
    word-break: break-all;
}
td.num-cell {
    text-align: right;
    font-variant-numeric: tabular-nums;
    color: var(--text-muted);
    white-space: nowrap;
}

/* Virtual table spacers */
.table-viewport td > * { display: block; }

/* ── Accordion sections (combined dashboard) ─────────────────────────── */
.path-section {
    background: var(--bg-card);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    margin-bottom: 0.75rem;
    overflow: hidden;
    transition: border-color 200ms;
}
.path-section.expanded {
    border-left: 2px solid var(--accent);
}
.path-header {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    padding: 1rem 1.25rem;
    cursor: pointer;
    user-select: none;
    transition: background 120ms;
}
.path-header:hover { background: var(--bg-card-hover); }
.path-toggle {
    color: var(--text-muted);
    transition: transform 200ms ease;
    flex-shrink: 0;
}
.path-section.expanded .path-toggle { transform: rotate(90deg); }
.path-name {
    font-size: 0.9rem;
    font-weight: 600;
    color: var(--text);
    font-family: ui-monospace, 'Cascadia Code', monospace;
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
}
.path-stats {
    font-size: 0.78rem;
    color: var(--text-muted);
    white-space: nowrap;
    flex-shrink: 0;
}
.path-body {
    overflow: hidden;
    max-height: 0;
    opacity: 0;
    transition: max-height 300ms ease, opacity 250ms ease;
}
.path-section.expanded .path-body {
    max-height: 9999px;
    opacity: 1;
}
.path-body-inner {
    padding: 1rem 1.25rem 1.25rem;
    border-top: 1px solid var(--border);
}
.path-summary-row {
    display: flex;
    gap: 0.75rem;
    flex-wrap: wrap;
    margin-bottom: 1.25rem;
}
.path-summary-row .card {
    flex: 1;
    min-width: 110px;
    padding: 0.875rem 0.75rem;
}
.path-summary-row .card .val { font-size: 1.35rem; }
.path-file-count {
    font-size: 0.78rem;
    color: var(--text-muted);
    margin: 0.5rem 0 0.375rem;
}
.lang-table, .file-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.82rem;
    margin-bottom: 0.875rem;
}
.lang-table th, .lang-table td,
.file-table th, .file-table td {
    padding: 0.4rem 0.625rem;
    text-align: left;
    border-bottom: 1px solid var(--border);
}
.lang-table th, .file-table th {
    font-size: 0.68rem;
    font-weight: 600;
    color: var(--text-muted);
    text-transform: uppercase;
    letter-spacing: 0.06em;
}
.file-row { cursor: pointer; }
.file-row:hover td { background: var(--bg-card-hover); }
.file-row td:first-child {
    font-family: ui-monospace, 'Cascadia Code', monospace;
    font-size: 0.78rem;
    word-break: break-all;
}
.file-row td:not(:first-child) {
    white-space: nowrap;
    color: var(--text-muted);
    font-variant-numeric: tabular-nums;
}

/* ── Source viewer panel ─────────────────────────────────────────────── */
#viewer {
    position: fixed;
    top: 0; right: 0; bottom: 0;
    width: min(720px, 100vw);
    background: var(--bg-card);
    border-left: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    transform: translateX(100%);
    transition: transform 250ms cubic-bezier(.4,0,.2,1);
    z-index: 100;
}
#viewer.open { transform: translateX(0); }
#viewer-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0.875rem 1.25rem;
    border-bottom: 1px solid var(--border);
    background: var(--bg-card);
    flex-shrink: 0;
}
#viewer-path {
    font-family: ui-monospace, monospace;
    font-size: 0.8rem;
    color: var(--text-muted);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
}
#viewer-close {
    background: none;
    border: 1px solid var(--border);
    color: var(--text-muted);
    border-radius: var(--radius);
    padding: 0.2rem 0.5rem;
    cursor: pointer;
    font-size: 0.875rem;
    transition: border-color 120ms, color 120ms;
    flex-shrink: 0;
}
#viewer-close:hover { border-color: var(--border-hover); color: var(--text); }
#viewer-body {
    flex: 1;
    overflow: auto;
    overflow-anchor: none;
    padding: 0;
    font-size: 0.82rem;
    line-height: 1.6;
}
#viewer-body pre[class*="language-"] { margin: 0; border-radius: 0; }
.vwindow { overflow: hidden; }
.vline { height: 20px; overflow: hidden; white-space: pre; }
.table-viewport td > * { display: block; padding: 0; }

/* ── Offline banner ─────────────────────────────────────────────────── */
#offline-banner {
    position: fixed;
    top: 0; left: 0; right: 0;
    z-index: 9999;
    background: var(--bg-card);
    color: var(--text);
    padding: 1rem 1.5rem;
    font-size: 0.85rem;
    border-bottom: 2px solid #f59e0b;
    line-height: 1.8;
    display: none;
}
#offline-banner strong { color: #f59e0b; }
#offline-banner code {
    background: var(--bg);
    border: 1px solid var(--border);
    padding: 1px 6px;
    border-radius: 4px;
    font-family: ui-monospace, monospace;
}
.banner-dismiss {
    float: right;
    background: none;
    border: 1px solid var(--border);
    color: var(--text-muted);
    padding: 3px 10px;
    cursor: pointer;
    border-radius: 4px;
}
```

**Step 1: Replace file contents** — paste the block above into `src/templates/src/dashboard.css`, replacing everything.

**Step 2: Verify no compile errors** — CSS has no compile step; just make sure there are no syntax issues by eye-checking.

---

## Task 2: Create src/templates/src/theme.ts

**Files:**
- Create: `src/templates/src/theme.ts`

**What to do:** New module. Reads localStorage key `"zz-theme"`, falls back to `prefers-color-scheme`, sets `data-theme` on `<html>`, and exports a toggle function. Import this in `main.ts` and `combined.ts`.

```typescript
const STORAGE_KEY = "zz-theme";
const root = document.documentElement;

function getSystemTheme(): "dark" | "light" {
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

export function initTheme(): void {
    const stored = localStorage.getItem(STORAGE_KEY) as "dark" | "light" | null;
    root.setAttribute("data-theme", stored ?? getSystemTheme());
}

export function toggleTheme(): void {
    const current = root.getAttribute("data-theme") === "dark" ? "light" : "dark";
    root.setAttribute("data-theme", current);
    localStorage.setItem(STORAGE_KEY, current);
}
```

**Step 1: Create the file** with the content above.

**Step 2: Verify it's importable** — no test needed, will fail at bundle step if broken.

---

## Task 3: Update template.html — single-path dashboard shell

**Files:**
- Rewrite: `src/templates/src/template.html`

**What to do:** Restructure the HTML to match the new design. Key changes:
- Add a no-FOUC inline script in `<head>` (sets `data-theme` before CSS renders)
- Replace the old `<header>` with the new three-row structure (accent bar, header row)
- Add `#theme-toggle` button with sun/moon SVGs
- Add `#sse-dot` span
- Wrap search in `.search-wrap` with icon + count badge
- Replace offline banner with CSS-var version
- Add `#search-count` span

**New file content:**

```html
<!doctype html>
<html lang="en">
    <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width,initial-scale=1" />
        <title>ZigZag Report</title>
        <!-- Theme: set data-theme before CSS renders to prevent flash -->
        <script>(function(){var t=localStorage.getItem('zz-theme')||(window.matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light');document.documentElement.setAttribute('data-theme',t);})();</script>
        <!-- @inject: dashboard.css -->
        <!-- @inject: prism-theme.css -->
    </head>
    <body>
        <div id="offline-banner">
            <strong>&#9888; Source files require a local server to load.</strong><br>
            Run: <code>zigzag serve</code> then open <code>http://localhost:8787</code>
            <button class="banner-dismiss" onclick="document.getElementById('offline-banner').style.display='none'">&#x2715; Dismiss</button>
        </div>
        <div class="accent-bar"></div>
        <header>
            <div class="header-left">
                <div class="wordmark">ZigZag</div>
                <h1 id="report-title">Code Report</h1>
                <p id="report-meta"></p>
            </div>
            <div class="header-right">
                <span id="sse-dot" title="Watch: live"></span>
                <button id="theme-toggle" title="Toggle theme" aria-label="Toggle theme">
                    <svg class="icon-sun" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"/></svg>
                    <svg class="icon-moon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>
                </button>
            </div>
        </header>
        <div class="container">
            <div class="section">
                <h2>Summary</h2>
                <div class="cards" id="cards"></div>
            </div>
            <div class="section">
                <h2>Languages</h2>
                <div id="chart-lang"></div>
            </div>
            <div class="section">
                <h2>File Size Distribution</h2>
                <div id="chart-size"></div>
            </div>
            <div class="section">
                <h2>Files</h2>
                <div class="search-wrap">
                    <svg class="search-icon" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/></svg>
                    <input type="text" id="search" placeholder="Search files and languages…" autocomplete="off" />
                    <button class="search-clear" id="search-clear" title="Clear search">&#x2715;</button>
                    <span class="search-count" id="search-count"></span>
                </div>
                <div id="files-table"></div>
            </div>
        </div>
        <div id="viewer">
            <div id="viewer-header">
                <span id="viewer-path"></span>
                <button id="viewer-close" title="Close (Esc)">&#x2715;</button>
            </div>
            <div id="viewer-body"></div>
        </div>
        <!-- @inject-text: dist/highlight.worker.js as prism-src -->
        <script type="application/json" id="rpt">__ZIGZAG_DATA__</script>
        <script>window.REPORT = JSON.parse(document.getElementById('rpt').textContent);</script>
        <!-- @inject: dist/bundle.js -->
    </body>
</html>
```

**Step 1:** Replace `src/templates/src/template.html` with the content above.

---

## Task 4: Update main.ts — wire theme toggle and search count

**Files:**
- Modify: `src/templates/src/main.ts`

**What to do:** Import `initTheme` and `toggleTheme`, call `initTheme()` first, wire the theme toggle button click. Also wire the search clear button and count badge. The search input currently lives in `table.ts` or similar — check where the `#search` listener is registered. (If table.ts does it, only add theme + clear here.)

**New `main.ts`:**

```typescript
import { M } from "./state";
import { renderHeader, renderCards } from "./header";
import { renderLangChart, renderSizeChart } from "./charts";
import { buildTableDOM, renderTable, getTotalCount } from "./table";
import { startWatchMode } from "./watch";
import { initTheme, toggleTheme } from "./theme";

// Theme must be the very first thing after module evaluation
initTheme();

// Wire theme toggle button
const themeBtn = document.getElementById("theme-toggle");
if (themeBtn) themeBtn.addEventListener("click", toggleTheme);

renderHeader();
renderCards();
renderLangChart();
renderSizeChart();

const tableViewport = buildTableDOM();
document.getElementById("files-table")!.appendChild(tableViewport);
renderTable();

// Wire search clear button + live count badge
const searchEl = document.getElementById("search") as HTMLInputElement | null;
const clearBtn = document.getElementById("search-clear") as HTMLButtonElement | null;
const countEl  = document.getElementById("search-count") as HTMLElement | null;

function updateSearchUI(): void {
    const q = searchEl?.value ?? "";
    if (clearBtn) clearBtn.classList.toggle("visible", q.length > 0);
    if (countEl) {
        const total = getTotalCount();
        countEl.textContent = q ? `${renderTable()} / ${total} files` : `${total} files`;
    }
}

if (searchEl) {
    searchEl.addEventListener("input", () => { renderTable(); updateSearchUI(); });
}
if (clearBtn) {
    clearBtn.addEventListener("click", () => {
        if (searchEl) { searchEl.value = ""; renderTable(); updateSearchUI(); }
    });
}
// Initial count
if (countEl) { const t = getTotalCount(); countEl.textContent = `${t} files`; }

if (M.watch_mode) {
    startWatchMode();
}
```

**IMPORTANT:** The above calls `renderTable()` for its return value (matched count). Check `table.ts` — if `renderTable()` does not currently return a number, add a return value. See Task 4b.

---

## Task 4b: Make table.ts export getTotalCount and renderTable return match count

**Files:**
- Modify: `src/templates/src/table.ts`

**What to do:** Read `table.ts` first. Then:
1. Export `getTotalCount(): number` — returns `F.length` (total files array from state)
2. Make `renderTable()` return the number of visible rows after filtering

Read the file, find the render function, add the return value and export. Do not change any rendering logic — minimal change only.

---

## Task 5: Add SSE status dot to watch.ts

**Files:**
- Modify: `src/templates/src/watch.ts`

**What to do:** The dot `#sse-dot` is in the header. When `startWatchMode()` connects, show the dot and update its class. Minimal addition — add a helper and call it at connection open/error. Add after the existing imports:

```typescript
function setSseDot(state: "live" | "reconnecting" | "hidden"): void {
    const dot = document.getElementById("sse-dot") as HTMLElement | null;
    if (!dot) return;
    dot.style.display = state === "hidden" ? "none" : "block";
    dot.classList.toggle("reconnecting", state === "reconnecting");
    dot.title = state === "live" ? "Watch: live" : "Watch: reconnecting…";
}
```

In `startWatchMode`, after `es = new EventSource(sseUrl)` add:
```typescript
setSseDot("live");
es.onopen = () => setSseDot("live");
es.onerror = () => { if (received) setSseDot("reconnecting"); };
```

Also call `setSseDot("live")` in `startPolling()` (polling is a degraded mode, still "live" from user's perspective — or use "reconnecting").

---

## Task 6: Add watch_mode + sse_url to combined JSON meta (Zig)

**Files:**
- Modify: `src/cli/commands/report/writers/html/html.zig`

**What to do:** In `writeCombinedHtmlReport`, the `meta` object is built around line 272. Add `watch_mode` and `sse_url` fields exactly like `writeHtmlReport` does (lines 41–51 of the same file). Add after the `"version"` field:

```zig
try ws.objectField("watch_mode");
try ws.write(cfg.watch);
if (cfg.watch and cfg.html_output) {
    const sse_url = try std.fmt.allocPrint(
        allocator,
        "http://127.0.0.1:{d}/__events",
        .{cfg.serve_port},
    );
    defer allocator.free(sse_url);
    try ws.objectField("sse_url");
    try ws.write(sse_url);
}
```

Also add `watch_mode?: boolean; sse_url?: string;` to the `CombinedMeta` interface in `src/templates/src/combined-types.ts`.

**Step 1:** Read `html.zig` lines 236–290 to confirm exact position.
**Step 2:** Add the Zig snippet after the `"version"` field in the combined meta object.
**Step 3:** Update `combined-types.ts` — add the two optional fields to `CombinedMeta`.

---

## Task 7: Update combined.html — new shell + remove old inline CSS

**Files:**
- Rewrite: `src/templates/src/combined.html`

**What to do:** Apply the same header pattern as `template.html`. Remove all the old inline `<style>` block (those styles now live in `dashboard.css` under accordion rules). Add the no-FOUC theme script, accent bar, search improvements.

```html
<!doctype html>
<html lang="en">
    <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width,initial-scale=1" />
        <title>ZigZag Combined Report</title>
        <script>(function(){var t=localStorage.getItem('zz-theme')||(window.matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light');document.documentElement.setAttribute('data-theme',t);})();</script>
        <!-- @inject: dashboard.css -->
        <!-- @inject: prism-theme.css -->
    </head>
    <body>
        <div id="offline-banner">
            <strong>&#9888; Source files require a local server to load.</strong><br>
            Run: <code>zigzag serve</code> then open <code>http://localhost:8787</code>
            <button class="banner-dismiss" onclick="document.getElementById('offline-banner').style.display='none'">&#x2715; Dismiss</button>
        </div>
        <div class="accent-bar"></div>
        <header>
            <div class="header-left">
                <div class="wordmark">ZigZag</div>
                <h1 id="report-title">Combined Report</h1>
                <p id="report-meta"></p>
            </div>
            <div class="header-right">
                <span id="sse-dot" title="Watch: live"></span>
                <button id="theme-toggle" title="Toggle theme" aria-label="Toggle theme">
                    <svg class="icon-sun" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"/></svg>
                    <svg class="icon-moon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>
                </button>
            </div>
        </header>
        <div class="container">
            <div class="section">
                <h2>Global Summary</h2>
                <div class="cards" id="cards"></div>
            </div>
            <div class="section">
                <h2>Paths</h2>
                <div class="search-wrap">
                    <svg class="search-icon" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/></svg>
                    <input type="text" id="search" placeholder="Search files, languages, or paths across all sections…" autocomplete="off" />
                    <button class="search-clear" id="search-clear" title="Clear search">&#x2715;</button>
                    <span class="search-count" id="search-count"></span>
                </div>
                <div id="path-sections"></div>
            </div>
        </div>
        <div id="viewer">
            <div id="viewer-header">
                <span id="viewer-path"></span>
                <button id="viewer-close" title="Close (Esc)">&#x2715;</button>
            </div>
            <div id="viewer-body"></div>
        </div>
        <!-- @inject-text: dist/highlight.worker.js as prism-src -->
        <script type="application/json" id="rpt">__ZIGZAG_DATA__</script>
        <script>window.COMBINED_REPORT = JSON.parse(document.getElementById('rpt').textContent);</script>
        <!-- @inject: dist/combined.js -->
    </body>
</html>
```

---

## Task 8: Update combined.ts — theme, SSE, search count, accordion CSS class

**Files:**
- Modify: `src/templates/src/combined.ts`

**What to do:** Four additions to the existing file:

**A) Imports at top — add:**
```typescript
import { initTheme, toggleTheme } from "./theme";
import { resetContent } from "./content";
```
(Keep existing imports. `resetContent` may already be imported via content.)

**B) At module load, before `renderGlobalSummary()` call — add:**
```typescript
initTheme();
const themeBtn = document.getElementById("theme-toggle");
if (themeBtn) themeBtn.addEventListener("click", toggleTheme);
```

**C) Replace the current search `filterAllSections` wiring at the bottom — update to:**
```typescript
const searchEl = document.getElementById("search") as HTMLInputElement | null;
const clearBtn = document.getElementById("search-clear") as HTMLButtonElement | null;
const countEl  = document.getElementById("search-count") as HTMLElement | null;

function updateSearchCount(q: string): void {
    if (!countEl) return;
    if (!q) {
        const total = R.paths.reduce((s, p) => s + p.files.length, 0);
        countEl.textContent = `${total} files`;
    } else {
        let matched = 0;
        R.paths.forEach((p) => {
            matched += p.files.filter((f) => matchesSearch(f, q)).length;
        });
        const total = R.paths.reduce((s, p) => s + p.files.length, 0);
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
```

**D) Add combined SSE watcher at the bottom:**
```typescript
// Watch mode: reload when combined.html is rewritten
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
        es.addEventListener("reload", () => { resetContent(); location.reload(); });
    } catch { /* SSE unavailable */ }
}
```

**E) Update `renderPathSection` HTML to use new CSS class structure:**

The accordion now relies on CSS for animation (`.path-body` with `max-height` transition). The body wrapper needs an inner div `.path-body-inner`. Update `renderPathSection` to output:

```typescript
return `
<div class="path-section${expanded ? " expanded" : ""}" data-root-path="${esc(p.root_path)}">
    <div class="path-header" role="button" tabindex="0">
        <span class="path-toggle">&#9658;</span>
        <span class="path-name">${esc(p.root_path)}</span>
        <span class="path-stats">${p.summary.source_files} files · ${fmt(p.summary.total_size_bytes)}</span>
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
            <p class="path-file-count" data-root="${esc(p.root_path)}">${p.files.length} files</p>
            <table class="file-table">
                <thead><tr><th>Path</th><th>Language</th><th>Lines</th><th>Size</th></tr></thead>
                <tbody class="file-tbody">${fileRows}</tbody>
            </table>
        </div>
    </div>
</div>`;
```

Update `attachSectionToggle` — remove the `body.style.display` toggle (CSS handles it now via `max-height`), just toggle the `expanded` class:

```typescript
function attachSectionToggle(section: HTMLElement): void {
    const header = section.querySelector<HTMLElement>(".path-header")!;
    header.addEventListener("click", () => { section.classList.toggle("expanded"); });
    header.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") { e.preventDefault(); header.click(); }
    });
}
```

---

## Task 9: Rebuild bundle

**Files:**
- Regenerated: `src/templates/dashboard.html`
- Regenerated: `src/templates/combined-dashboard.html`

**Step 1: Run the bundler**
```bash
cd /home/anze/Projects/zigzag
python3 src/templates/bundle.py
```

**Expected output:**
```
  dist/bundle.js  ...kb
  dist/highlight.worker.js  ...kb
  dist/combined.js  ...kb
bundle.py: building ...
Bundled .../template.html -> .../dashboard.html (...bytes)
Bundled .../combined.html -> .../combined-dashboard.html (...bytes)
```

If esbuild errors: TypeScript type errors in the new imports will appear. Fix them before proceeding.

---

## Task 10: Build Zig + run tests

**Step 1: Build**
```bash
zig build
```
Expected: no errors.

**Step 2: Run tests**
```bash
make test
```
Expected: 191 passed; 1 skipped; 0 failed.

**Step 3: Release build smoke test**
```bash
zig build -Doptimize=ReleaseFast
```

---

## Task 11: Smoke test the running dashboards

**Step 1:** Run zigzag against its own codebase
```bash
./zig-out/bin/zigzag run
```

**Step 2:** Verify files exist
```bash
ls zigzag-reports/
# should contain: combined.html, combined-content.json, .claude/, docs/, src/
ls zigzag-reports/src/
# should contain: report.html, report-content.json, report.md, ...
```

**Step 3:** Open `zigzag-reports/combined.html` in a browser (file:// or via `zigzag watch`) and verify:
- Accent bar visible at top
- Gradient title renders
- Theme toggle switches dark/light
- Theme persists on reload (check DevTools → Application → localStorage → `zz-theme`)
- Stats cards show hover lift on mouse-over
- Path sections expand/collapse with smooth animation
- Search count badge updates while typing
- Search clear button appears/disappears

**Step 4:** Open `zigzag-reports/src/report.html` and verify same header + cards + search improvements.

---

## Task 12: Commit

```bash
git add src/templates/src/dashboard.css \
        src/templates/src/theme.ts \
        src/templates/src/template.html \
        src/templates/src/combined.html \
        src/templates/src/combined.ts \
        src/templates/src/combined-types.ts \
        src/templates/src/main.ts \
        src/templates/src/watch.ts \
        src/templates/src/table.ts \
        src/templates/src/content.ts \
        src/templates/dashboard.html \
        src/templates/combined-dashboard.html \
        src/cli/commands/report/writers/html/html.zig

git commit -m "feat: Shadcn+Aceternity redesign, theme switcher, watch-mode SSE fix

- New design system: CSS custom properties, data-theme attribute switching,
  zinc/indigo palette matching Shadcn OKLCH neutrals
- Light/dark theme toggle: persisted to localStorage, respects
  prefers-color-scheme on first visit
- No-FOUC inline script in both HTML templates
- Accent bar: 3px animated gradient at top of page
- Stat cards: hover lift + accent glow (Aceternity touch)
- Search: icon + live count badge + clear button; distinct placeholder
  text per dashboard clarifies search scope
- Accordion sections: CSS max-height animation, accent left border when
  expanded, chevron rotation
- SSE status dot in header: green=live, amber=reconnecting
- Combined dashboard: connects EventSource for reload events so watch
  mode auto-refreshes when combined.html is rewritten
- Combined report JSON meta: adds watch_mode + sse_url fields"
```
