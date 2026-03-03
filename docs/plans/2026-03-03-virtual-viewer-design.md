# Virtual Code Viewer Design

**Date:** 2026-03-03
**Status:** Approved

## Problem

The source viewer in `dashboard.js` dumps the entire file content into a single `<code>` element and sends it all to the Prism worker for highlighting. For large files this causes:

- Slow initial render (all DOM nodes created at once)
- Long highlight times (entire file sent to worker in one message)
- High memory usage (full highlighted HTML string held in memory)

Additionally, the Zig grammar has a regex bug that highlights field-access dots (e.g. `std.ArrayList`) as operators (cyan colour).

---

## Goals

1. Virtual scroll the code viewer — render only visible lines + overscan
2. Chunk-cached syntax highlighting — highlight in 200-line chunks, cache results
3. Line numbers in the gutter
4. Fix the Zig operator regex bug

---

## Thresholds

| Constant              | Value     | Meaning                                      |
|-----------------------|-----------|----------------------------------------------|
| `VIRT_LINE_THRESHOLD` | 500 lines | Files above this use the virtual viewer      |
| `VIRT_BYTE_THRESHOLD` | 200 KB    | Files above this use the virtual viewer      |
| `LINE_HEIGHT`         | 21 px     | `14px` monospace × 1.5 line-height (CSS+JS)  |
| `OVERSCAN`            | 15 lines  | Extra lines rendered above/below the viewport|
| `CHUNK_SIZE`          | 200 lines | Unit of work sent to the Prism worker        |

If **either** threshold is exceeded the virtual viewer is used.

---

## Entry Point Split

`openViewer(f)` continues to fetch content via `fetchContent`. After receiving the raw string:

```
if lines > VIRT_LINE_THRESHOLD OR byteLength > VIRT_BYTE_THRESHOLD:
    openVirtualViewer(lines[], langKey)
else:
    openSimpleViewer(content, langKey)   ← current behaviour + line numbers
```

---

## DOM Structure (virtual path)

```
#viewer-body  (overflow-y: auto, fixed height via CSS)
└── .vscroll  (height: totalLines × LINE_HEIGHT px, position: relative)
    └── .vwindow  (position: absolute, top: startLine × LINE_HEIGHT px)
        ├── .vline  (display: flex, height: LINE_HEIGHT px)
        │   ├── .ln   (line number, fixed width, muted, user-select: none)
        │   └── .lc   (code content, flex: 1, white-space: pre)
        └── …
```

On each RAF-throttled scroll event:

1. `startLine = max(0, floor(scrollTop / LINE_HEIGHT) - OVERSCAN)`
2. `endLine   = min(totalLines, ceil((scrollTop + viewH) / LINE_HEIGHT) + OVERSCAN)`
3. Replace `.vwindow` innerHTML with plain-text lines for the new window
4. Set `.vwindow` `top = startLine × LINE_HEIGHT + "px"`
5. Request highlight chunks covering `[startLine, endLine)`

---

## Line Number Gutter

`.ln` width is set once on open:

```js
var gutterWidth = String(totalLines).length + "ch";
```

CSS properties:
- `text-align: right`
- `padding-right: 1rem`
- `color: var(--muted)`
- `user-select: none`
- `flex-shrink: 0`

`.lc` properties:
- `flex: 1`
- `white-space: pre`
- `overflow-x: auto`

The **non-virtual path** (small files) also gets line numbers, rendered as a two-column `<table>` (gutter + code) so selection works correctly and no virtual machinery is needed.

---

## Chunk Highlighting Cache

```
chunkIndex = floor(lineIndex / CHUNK_SIZE)
```

**Per-file cache** (object, cleared on viewer close):

```js
hlChunkCache = {}   // chunkIndex → string[]  (one highlighted HTML string per line)
hlChunkPending = {} // chunkIndex → true       (request in-flight)
```

**Flow:**

1. Render visible window as **plain text** immediately
2. For each chunk index `c` covering `[startLine, endLine)`:
   - Cache hit → apply highlighted HTML to `.lc` elements for those lines now
   - In-flight → skip (reply will patch the DOM when it arrives)
   - Miss → mark pending, send `{ id, code: chunkLines.join('\n'), language }` to worker
3. Worker reply → store result in `hlChunkCache[c]` → if viewer token still valid, patch `.lc` elements for that chunk's lines currently in the DOM

**Cancellation:** `viewerToken` (existing) — any worker reply with a stale token is discarded.

**Cache eviction:** `hlChunkCache` and `hlChunkPending` are reset in `closeViewer()` and at the start of each `openViewer()` call.

---

## Zig Operator Fix

File: `src/templates/src/highlight-worker.js`

```js
// Before (broken — [^.]\. matches field-access dots as operators)
operator: /\.?\.{2,3}|[*!%&+\-/<=>|~^?]|[^.]\./,

// After (fixed)
operator: /\.{2,3}|[*!%&+\-/<=>|~^?]/,
```

`\.{2,3}` matches the `..` and `...` range operators. Single-character operators unchanged. Field-access `.` is punctuation, not an operator.

After this change, `bundle.py` must be re-run to regenerate `dashboard.html`.

---

## Files Changed

| File | Change |
|------|--------|
| `src/templates/src/dashboard.js` | Add `openVirtualViewer`, threshold check in `openViewer`, line numbers on non-virtual path |
| `src/templates/src/dashboard.css` | Add `.vscroll`, `.vwindow`, `.vline`, `.ln`, `.lc`, non-virtual line-number table styles |
| `src/templates/src/highlight-worker.js` | Fix Zig operator regex |
| `src/templates/dashboard.html` | Regenerated by `bundle.py` (committed) |

No Zig source changes required.

---

## Non-Goals

- Horizontal virtual scroll (long lines are handled by `overflow-x: auto` on `.lc`)
- Persistent highlight cache across file opens (memory cost not worth it)
- Syntax highlighting for binary files (unchanged — not shown in viewer)
