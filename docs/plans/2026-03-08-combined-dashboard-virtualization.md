# Combined Dashboard Virtualization — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the naive O(n) file-row rendering in the combined dashboard with a per-section virtual scroll table so the browser never freezes regardless of repository size.

**Architecture:** A new `VirtualTable` class (same algorithm as the existing `table.ts`) is lazily instantiated per path section on first expand. Each instance owns a fixed-height `.table-viewport` div and renders only the visible rows ±10 overscan. `combined.ts` is refactored to mount VirtualTable instances instead of building innerHTML strings.

**Tech Stack:** TypeScript (no test framework — verification is bundle + browser smoke-test), esbuild via `bundle.py`, CSS in `dashboard.css`.

---

## Before you start

- Working directory: `src/templates/src/`
- Run the bundler: `python3 src/templates/bundle.py` (takes ~5s)
- Serve the output: `zigzag serve` then open `http://127.0.0.1:8787/combined.html`
- The test repository is Next.js source; expanding the `.` section with 24k files is the freeze trigger

---

### Task 1: Add `.path-section .table-viewport { max-height: 600px; }` to CSS

**Files:**
- Modify: `src/templates/src/dashboard.css`

**Step 1: Find the right place — look for `.section-search` which was added last session**

Open `dashboard.css`, find the `.section-search` block near the bottom of the file. The new rule goes right after it, before the closing of the file.

**Step 2: Add the rule**

Find the block:
```css
.section-search::placeholder { color: var(--text-subtle); }
```

After it, add:
```css

/* ── Combined-dashboard per-section virtual table ───────────────────────── */
.path-section .table-viewport {
    max-height: 600px;
}
```

**Step 3: Bundle and verify CSS is present in combined-dashboard.html**

```bash
python3 src/templates/bundle.py
grep -c "max-height: 600px" src/templates/combined-dashboard.html
# Expected: 1
```

**Step 4: Commit**

```bash
git add src/templates/src/dashboard.css src/templates/combined-dashboard.html src/templates/dashboard.html
git commit -m "style: cap combined section file tables at 600px for virtual scroll"
```

---

### Task 2: Create `virtual-table.ts`

**Files:**
- Create: `src/templates/src/virtual-table.ts`

This file implements a self-contained `VirtualTable` class. It is modelled exactly on `table.ts` but scoped to `CombinedFile` rows and has no sort logic.

**Step 1: Create the file with the full implementation**

```typescript
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
        this.renderVisible();
    }

    /** Return the DOM element to mount into the page. */
    getElement(): HTMLElement {
        return this.viewport;
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
                "<td><span>" + esc(f.language || "\u2014") + "</span></td>" +
                "<td><span>" + fmtNum(f.lines) + "</span></td>" +
                "<td><span>" + fmt(f.size) + "</span></td>";
            frag.appendChild(tr);
        }
        this.tbody.insertBefore(frag, this.botSpacer);
    }
}
```

**Step 2: Verify esbuild picks it up (it's an import, not a standalone entry point)**

```bash
python3 src/templates/bundle.py 2>&1
# Expected: no errors, "Done." at end
```

If esbuild errors, check the import path and TypeScript syntax.

**Step 3: Verify the class appears in the combined bundle**

```bash
grep -c "VirtualTable\|virtual-table\|scheduleRender" src/templates/combined-dashboard.html
# Expected: > 0
```

**Step 4: Commit**

```bash
git add src/templates/src/virtual-table.ts src/templates/combined-dashboard.html
git commit -m "feat: add VirtualTable class for combined dashboard per-section virtual scroll"
```

---

### Task 3: Refactor `combined.ts` — remove eager row generation

**Files:**
- Modify: `src/templates/src/combined.ts`

The goal of this task is only to remove the eager rendering. Do not wire up VirtualTable yet — keep it compiling and visually working (sections will just be empty after this step).

**Step 1: Remove `fileRows` from `renderPathSection()`**

Find in `combined.ts`:
```typescript
    const fileRows = p.files.map((f) => renderFileRow(f)).join("");
```
Delete that line.

**Step 2: Replace the file table HTML with a mount point**

Find:
```typescript
            <table class="file-table">
                <thead><tr><th>Path</th><th>Language</th><th>Lines</th><th>Size</th></tr></thead>
                <tbody class="file-tbody">${fileRows}</tbody>
            </table>
```
Replace with:
```typescript
            <div class="vtable-mount"></div>
```

**Step 3: Remove `renderFileRow` function** (it's no longer called)

Find and delete the entire function:
```typescript
function renderFileRow(f: CombinedFile): string {
    return `<tr class="file-row" data-path="${esc(f.path)}" data-root="${esc(f.root_path)}">
        <td>${esc(f.path)}</td>
        <td>${esc(f.language)}</td>
        <td>${f.lines.toLocaleString()}</td>
        <td>${fmt(f.size)}</td>
    </tr>`;
}
```

**Step 4: Bundle and verify no compile errors**

```bash
python3 src/templates/bundle.py 2>&1
# Expected: clean build, no errors
```

**Step 5: Commit**

```bash
git add src/templates/src/combined.ts src/templates/combined-dashboard.html
git commit -m "refactor: remove eager file-row generation from combined dashboard path sections"
```

---

### Task 4: Wire up `VirtualTable` in `combined.ts`

**Files:**
- Modify: `src/templates/src/combined.ts`

**Step 1: Add import at the top of `combined.ts`**

After the existing imports, add:
```typescript
import { VirtualTable } from "./virtual-table";
```

**Step 2: Add the section tables map** (module-level, after `const R = ...`)

```typescript
const sectionTables = new Map<string, VirtualTable>();
```

**Step 3: Add a helper to get the current filtered files for a path**

Add this function after `matchesSearch`:
```typescript
function currentFilteredFiles(pathData: CombinedPathReport): CombinedFile[] {
    const q = searchEl ? searchEl.value.trim().toLowerCase() : "";
    return q ? pathData.files.filter((f) => matchesSearch(f, q)) : pathData.files;
}
```

**Step 4: Extend `attachSectionToggle` to mount VirtualTable on first expand**

Replace the existing `attachSectionToggle`:
```typescript
function attachSectionToggle(section: HTMLElement, pathData: CombinedPathReport): void {
    const header = section.querySelector<HTMLElement>(".path-header")!;
    const mount = section.querySelector<HTMLElement>(".vtable-mount")!;
    const rootPath = pathData.root_path;

    function maybeMount(): void {
        if (!section.classList.contains("expanded")) return;
        if (sectionTables.has(rootPath)) return;
        const vtable = new VirtualTable(openCombinedViewer);
        vtable.setFiles(currentFilteredFiles(pathData));
        mount.appendChild(vtable.getElement());
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
```

**Step 5: Update `attachSectionSearch` to call `vtable.setFiles`**

Replace the existing `attachSectionSearch`:
```typescript
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
```

**Step 6: Update `filterAllSections` to call `vtable.setFiles`**

Replace the existing `filterAllSections`:
```typescript
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
```

**Step 7: Update `renderPathSections` to pass `pathData` to `attachSectionToggle`**

Replace the existing `renderPathSections`:
```typescript
function renderPathSections(): void {
    const container = document.getElementById("path-sections")!;
    container.innerHTML = R.paths.map((p, i) => renderPathSection(p, i)).join("");
    container.querySelectorAll<HTMLElement>(".path-section").forEach((section, i) => {
        attachSectionToggle(section, R.paths[i]);
        attachSectionSearch(section, R.paths[i]);
    });
}
```

Note: `attachRowListeners` calls are removed — VirtualTable handles its own delegated click.

**Step 8: Remove `attachRowListeners` function** — it's no longer used from `combined.ts`.

Find and delete the entire function:
```typescript
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
```

**Step 9: Bundle**

```bash
python3 src/templates/bundle.py 2>&1
# Expected: clean build
```

**Step 10: Commit**

```bash
git add src/templates/src/combined.ts src/templates/combined-dashboard.html
git commit -m "feat: wire VirtualTable into combined dashboard — lazy per-section virtual scroll"
```

---

### Task 5: Smoke test in browser

**Step 1: Run the server**

```bash
zig build && zigzag run   # or just serve an existing report
zigzag serve --port 8787
```

Or if you have an existing `zigzag-reports/combined.html`:
```bash
python3 -m http.server 8787 --directory zigzag-reports
```

**Step 2: Open `http://127.0.0.1:8787/combined.html`**

**Step 3: Verify these behaviours**

| Action | Expected |
|---|---|
| Page load | Instant — no file rows in DOM yet |
| Expand first section (24k files) | Instant — only ~20-25 rows visible |
| Scroll file table | Rows render smoothly as you scroll |
| Search within section | File count updates, virtual table re-renders from filtered list |
| Global search | All expanded sections update counts; mounted VirtualTables update |
| Expand a second section after global search | Section opens pre-filtered |
| Scroll to bottom of 24k section | Bottom spacer height = `(24666 - end) * 40` px; no blank gap |
| Click a file row | Viewer opens with correct file content |
| Hover a file row | Content pre-fetch fires (check Network tab, no visible effect) |

**Step 4: Check DOM size in DevTools**

Open DevTools → Elements. Expand a section. The `<tbody>` inside `.table-viewport` should have ~20-30 `<tr>` elements, not 24,000.

**Step 5: If anything is broken, check the console first** — missing `vtable-mount`, wrong `rootPath` key, or `setFiles` called before mount.

---

### Task 6: Final cleanup and PR prep

**Step 1: Remove `src/wow.zig`** (scratch file from a previous session)

```bash
rm src/wow.zig
```

**Step 2: Run Zig tests to confirm nothing is broken on the backend**

```bash
make test
# Expected: all tests pass
```

**Step 3: Commit cleanup**

```bash
git add -A
git commit -m "chore: remove scratch file src/wow.zig"
```

**Step 4: Stage all uncommitted changes from this dev branch**

```bash
git status
git diff --stat HEAD
```

Confirm the only modified/added files are the ones expected from this plan plus prior session work.
