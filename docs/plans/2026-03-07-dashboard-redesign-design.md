# Dashboard Redesign — Design Specification

**Date:** 2026-03-07
**Scope:** Both dashboards (combined + single-path `report.html`) + watch mode SSE fix
**Style:** Shadcn base + Aceternity accents

---

## Goals

1. Modernise both dashboards with a Shadcn neutral palette and selective Aceternity motion accents.
2. Add a light/dark theme switcher that respects `prefers-color-scheme` and persists to `localStorage`.
3. Improve search UX with clear scoping labels and a live result count.
4. Fix watch mode: combined dashboard must auto-refresh on SSE `reload` event; single-path already works.

---

## Design Tokens

All tokens live in CSS custom properties on `:root`. Theme is controlled by `data-theme="dark"|"light"` on `<html>`.

### Dark (`oklch` reference)

| Token              | Value       | Notes                              |
|--------------------|-------------|-------------------------------------|
| `--bg`             | `#111113`   | oklch 0.145 — lifted, not near-black |
| `--bg-card`        | `#1c1c20`   | oklch 0.205 — visibly lighter       |
| `--bg-card-hover`  | `#232329`   |                                     |
| `--border`         | `#2e2e33`   | oklch 0.269 — subtle, visible       |
| `--border-hover`   | `#3f3f46`   | zinc-700                            |
| `--text`           | `#fafafa`   | zinc-50 / oklch 0.985               |
| `--text-muted`     | `#a1a1aa`   | zinc-400 / oklch 0.708              |
| `--text-subtle`    | `#52525b`   | zinc-600                            |
| `--accent`         | `#6366f1`   | indigo-500                          |
| `--accent-glow`    | `rgba(99,102,241,0.12)` |                        |
| `--radius`         | `0.625rem`  |                                     |

### Light (`oklch` reference)

| Token              | Value       | Notes                               |
|--------------------|-------------|--------------------------------------|
| `--bg`             | `#fafafa`   | zinc-50 / oklch 0.985 — off-white   |
| `--bg-card`        | `#ffffff`   | oklch 1.0 — white cards             |
| `--bg-card-hover`  | `#f4f4f5`   | zinc-100 / oklch 0.96               |
| `--border`         | `#e4e4e7`   | zinc-200 / oklch 0.922              |
| `--border-hover`   | `#d4d4d8`   | zinc-300                            |
| `--text`           | `#09090b`   | zinc-950 / oklch 0.145              |
| `--text-muted`     | `#71717a`   | zinc-500 / oklch 0.556              |
| `--text-subtle`    | `#d4d4d8`   | zinc-300                            |
| `--accent`         | `#4f46e5`   | indigo-600                          |
| `--accent-glow`    | `rgba(79,70,229,0.08)` |                         |
| `--radius`         | `0.625rem`  |                                     |

### Theme persistence

```
1. Read localStorage key "zz-theme"
2. If absent → match prefers-color-scheme media query
3. Set data-theme="dark"|"light" on <html> (before first paint to avoid flash)
4. Toggle button writes chosen value back to localStorage
```

---

## Components

### Header

Full-width strip, `1px var(--border)` bottom edge.

- **Top accent bar:** 3px `height`, slow-cycling gradient (`indigo → violet → indigo`, 6 s keyframe loop). Only animated element in the header.
- **Left:** `ZigZag` wordmark (`--text-subtle`, small-caps, `0.75rem`); below it the report title in gradient text (`linear-gradient(to right, var(--text), var(--text-muted))`, `background-clip: text`).
- **Right:** theme toggle button — 36×36px, round (`border-radius: 50%`), `--bg-card` fill, `1px var(--border)` ring; sun SVG in light mode, moon SVG in dark mode; 200 ms `opacity` crossfade between icons. Also: SSE status dot (see Watch Mode).

### Stat Cards

5-column responsive grid (`repeat(auto-fit, minmax(140px, 1fr))`).

Each card:
- Background: `--bg-card`, border: `1px var(--border)`, radius: `--radius`, padding: `1.5rem 1.25rem`
- **Value:** `1.75rem`, `font-weight: 700`, `font-variant-numeric: tabular-nums`, `--text`
- **Label:** `0.7rem`, uppercase, `letter-spacing: 0.08em`, `--text-muted`
- **Hover:** `transform: translateY(-2px)` + `box-shadow: 0 0 0 1px var(--border-hover), 0 4px 16px var(--accent-glow)`
- Transition: `150ms ease` on `transform` and `box-shadow`

Cards for **combined dashboard:** Paths, Source Files, Binary Files, Total Lines, Total Size
Cards for **single-path dashboard:** Source Files, Binary Files, Total Lines, Total Size, Languages (count)

### Search Bar

Sits below stat cards, full width.

- Container: `--bg-card`, `1px var(--border)`, `--radius`, `0.875rem` text, flex row
- Left: magnifying glass SVG icon in `--text-subtle`
- Input: grows to fill, no native outline; `::placeholder` color: `--text-subtle`
- **Focus state:** `border-color: var(--accent)`, `box-shadow: 0 0 0 3px rgba(var(--accent-rgb), 0.15)`
- Right: live count badge — `"156 files"` at rest, `"12 / 156 files"` while filtering; pill style in `--bg`, `--text-muted`
- Clear (`×`) button: appears only when input is non-empty, `--text-subtle` colour

**Placeholder text:**
- Combined dashboard: `Search files, languages, or paths across all sections…`
- Single-path dashboard: `Search files and languages…`

### File Table

- `thead`: sticky within its scroll container; `--text-muted`, `0.7rem`, uppercase, `letter-spacing: 0.06em`; `1px var(--border)` bottom only
- `tbody` rows: `1px var(--border)` bottom only (no zebra striping); hover → `background: var(--bg-card-hover)`; `cursor: pointer`
- **Path column:** `font-family: monospace`, `0.8rem`, `flex-grow: 1`
- **Language / Lines / Size:** fixed width, `font-variant-numeric: tabular-nums`, right-aligned

### Accordion Sections (combined dashboard only)

Each path is a standalone card block:

- Container: `--bg-card`, `1px var(--border)`, `--radius`, `overflow: hidden`, `margin-bottom: 0.75rem`
- **Header row:** `1rem` padding, flex row; left: path name (bold, `0.9rem`); right: file count + total size in `--text-muted`; far-right: chevron SVG
- **Chevron:** rotates `0°→90°` on expand, `200ms ease`
- **Expanded state:** `border-left: 2px solid var(--accent)` on the card container
- **Body:** language mini-table + file table; reveal via `max-height` transition (`0→9999px`) + `opacity` (`0→1`), `250ms ease`
- First section expanded by default; all others collapsed

---

## Watch Mode (SSE fix)

### Problem
Combined dashboard never connected to SSE; `exec.zig` served the per-path subdir instead of the base output dir, making `combined.html` unreachable. Both issues were fixed in a prior commit (`c42dd0b`). This design covers the remaining piece: SSE listening inside `combined.ts`.

### Solution

**Zig side (`writeCombinedHtmlReport`):**
Add `watch_mode: bool` and `sse_url: string` fields to the embedded JSON meta when `cfg.watch` is true. Single-path already does this; combined must match.

**TypeScript side:**
Extract a shared `connectWatch(sseUrl: string, onReport?: (d: unknown) => void): void` function in `watch.ts` (or a new `sse.ts`). Both dashboards call it on load if `meta.watch_mode === true`.

- `report` SSE event (single-path): patch data in place — existing behaviour, no change.
- `reload` SSE event (combined): `location.reload()` — combined.html has been rewritten.
- **Reconnection:** `EventSource` auto-reconnects; on reconnect show amber dot; on open show green dot.

**SSE status dot (header, both dashboards):**
- `●` green (`#22c55e`) = connected
- `●` amber (`#f59e0b`) = reconnecting
- Hidden entirely when `watch_mode === false`

**Zig debounce flush (already done in `c42dd0b`):**
After `writeCombinedReport()`, call `sse_server.?.broadcastReload()` — triggers browser reload.

---

## File Changeset Summary

| File | Change |
|------|--------|
| `src/templates/src/dashboard.css` | Full rewrite with design tokens, new component styles |
| `src/templates/src/theme.ts` | New — theme detection, toggle, localStorage persistence |
| `src/templates/src/watch.ts` | Add `connectWatch()` and status dot logic |
| `src/templates/src/combined.ts` | Wire theme toggle, status dot, updated search + accordions |
| `src/templates/src/template.html` | Updated structure: accent bar, theme toggle, search count badge |
| `src/templates/src/combined.html` | Updated structure: same header pattern, accordion structure |
| `src/cli/commands/report/writers/html/html.zig` | Add `watch_mode`/`sse_url` fields to combined report JSON meta |
| `src/templates/bundle.py` | Add `theme.ts` to esbuild entry points if kept separate; otherwise barrel-import |

---

## Out of Scope

- Virtual scroll viewer reskin (viewer.ts) — keep existing behaviour, inherit new CSS tokens only
- Prism theme — keep existing Tomorrow Night theme
- Mobile responsiveness — accordion and cards should reflow naturally; no custom mobile work planned
- Animation beyond the three approved Aceternity touches (gradient bar, card hover lift, section expand/collapse)
