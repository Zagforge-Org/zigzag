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
| `LINE_HEIGHT`         | 20 px     | JS constant must match CSS `.vline { height: 20px }` exactly |
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
#viewer-body  (overflow: auto; overflow-anchor: none — prevents scroll-anchor feedback loop)
├── spacerTop  (plain div — height: start × LINE_HEIGHT px — pushes vwindow down)
├── .vwindow   (height: (end - start) × LINE_HEIGHT px — pinned before innerHTML clear)
│   ├── .vline  (display: flex, height: 20px, overflow: hidden)
│   │   ├── .ln   (line number, fixed width, user-select: none)
│   │   └── .lc   (code content, white-space: pre)
│   └── …
└── spacerBot  (plain div — height: (total - end) × LINE_HEIGHT px)
```

**Important:** `overflow-anchor: none` on `#viewer-body` is critical. Without it, the browser's CSS Scroll Anchoring feature sees `spacerTop` growing as the user scrolls down and automatically adjusts `scrollTop` upward to keep the anchor element stable — which fires another scroll event → RAF → spacerTop grows more → loop continues until the bottom of the file.

On each RAF-throttled scroll event:

1. `start = max(0, floor(scrollTop / LINE_HEIGHT) - OVERSCAN)`
2. `end   = min(totalLines, ceil((scrollTop + viewH) / LINE_HEIGHT) + OVERSCAN)`
3. Pin `.vwindow` height to `(end - start) × LINE_HEIGHT + "px"` **before** clearing innerHTML (prevents `scrollHeight` collapse mid-render)
4. Set `spacerTop.height = start × LINE_HEIGHT + "px"`
5. Set `spacerBot.height = (total - end) × LINE_HEIGHT + "px"`
6. Replace `.vwindow` innerHTML with plain-text lines for the new window
7. Request highlight chunks covering `[start, end)`

---

## Line Number Gutter

`.ln` width is set once on open. The formula **must include padding** because `box-sizing: border-box` would otherwise cause the padding to eat into the `ch` content area, leaving near-zero space for the digit characters:

```js
var digits = String(totalLines).length;
var gutterW = "calc(" + digits + "ch + 2rem)"; // 2rem = 1rem left + 1rem right padding
```

The `ch` unit is relative to the monospace font's `0` character width (~7.8px in 13px Consolas). At 4-digit line numbers with `virtGutterW = "4ch"` the numbers would overflow the gutter; `"calc(4ch + 2rem)"` gives exactly `4ch` of digit content plus room for both padding sides.

CSS properties for `.vline .ln`:
- `flex-shrink: 0`
- `padding: 0 1rem 0 1rem`
- `text-align: right`
- `color: #6c757d`
- `user-select: none`

CSS properties for `.vline .lc`:
- `flex: none`
- `white-space: pre`
- `padding-right: 1rem`

**Horizontal overflow:** `#viewer-body` handles horizontal scroll. The `.vwindow` gets a one-time `style.minWidth` set at open time based on a pre-scan of the longest line:

```js
var maxLen = 0;
for (var i = 0; i < lines.length; i++) {
    if (lines[i].length > maxLen) maxLen = lines[i].length;
}
win.style.minWidth = "calc(" + (digits + maxLen) + "ch + 3rem)";
```

This prevents the horizontal scrollbar from appearing/disappearing mid-render (which would cause `clientHeight` to oscillate and destabilise the virtual scroll calculations).

The **non-virtual path** (small files) also gets line numbers, rendered as a two-column `<table>` (gutter + code) so selection works correctly and no virtual machinery is needed. Same `calc(Nch + 2rem)` formula applies to `numWidth` there.

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
| `src/templates/src/dashboard.js` | Add `openVirtualViewer`, threshold check in `openViewer`, line numbers on non-virtual path, CRLF normalization, pre-computed `minWidth`, vwindow height pinning |
| `src/templates/src/dashboard.css` | Add `.vwindow`, `.vline`, `.ln`, `.lc`, non-virtual line-number table styles; `overflow-anchor: none` on `#viewer-body`; scope `td > *` rule to `.table-viewport` |
| `src/templates/src/highlight-worker.js` | Fix Zig operator regex |
| `src/templates/dashboard.html` | Regenerated by `bundle.py` (committed) |

No Zig source changes required.

---

## Non-Goals

- Horizontal virtual scroll (long lines handled by `overflow-x: auto` on `#viewer-body`)
- Persistent highlight cache across file opens (memory cost not worth it)
- Syntax highlighting for binary files (unchanged — not shown in viewer)

---

## Post-Implementation Bug Fixes

These bugs were found during testing and fixed after the initial implementation.

### 1. Row height ~36px instead of 20px

**Cause:** `td.ln` and `td.lc` in the `ln-table` had `0.5rem` top and bottom padding. `white-space: pre` on `.lc` caused the cell to expand to match content height rather than being fixed.

**Fix:** Remove all vertical padding from `td.ln` and `td.lc`. Padding is `0 1rem 0 1rem` (sides only).

### 2. CRLF files rendered multi-line

**Cause:** `content.split("\n")` on Windows-style files leaves `\r` at each line end. `white-space: pre` on `.lc` renders `\r` as an additional newline character, making every line appear twice its height.

**Fix:** Normalize before splitting:
```js
var content = (raw || "(binary or empty)").replace(/\r\n/g, "\n").replace(/\r/g, "\n");
```

### 3. `.vline` height not enforced (overflow leaks)

**Cause:** Without `overflow: hidden` on `.vline`, any content taller than 20px (e.g., from a `\r` artefact before the CRLF fix) would spill into the spacer region, corrupting `scrollHeight` and causing erratic scroll jumps.

**Fix:** Added `overflow: hidden` to `.vline` in CSS.

### 4. Prism `<span>` tokens on separate lines (simple viewer)

**Cause:** The rule `td > * { display: block; padding: 0.4rem 0.75rem }` was global and applied to every `td` child, including Prism's `<span>` elements inside `td.lc`. Each syntax token became a block-level element with vertical padding, producing blank lines between every token.

**Fix:** Scoped the rule to `.table-viewport td > *` (and related hover/first-child rules). The virtual viewer's `.vline .ln` and `.vline .lc` are `<span>` elements inside `<div>` rows, so they were unaffected.

### 5. Line numbers overlapping code at 4+ digit line numbers

**Cause:** `virtGutterW = "4ch"` with `box-sizing: border-box` and `padding: 0 1rem 0 1rem` (2rem total). The 2rem padding consumed the entire `4ch` width (`4 × ~7.8px = 31px < 32px = 2rem`), leaving ~0px for the digit characters — numbers overflowed into the code area.

**Fix:** `virtGutterW = "calc(" + digits + "ch + 2rem)"` so the content area is exactly `digits ch` regardless of padding.

### 6. Scroll sensitivity from `scrollWidth` reads in RAF loop

**Cause:** Reading `scrollWidth` inside the RAF callback (to track the widest rendered line) forced a full layout flush on every animation frame. If the horizontal scrollbar appeared or disappeared between frames, `clientHeight` changed, causing the visible range calculation to oscillate and producing erratic large scroll jumps on long files.

**Fix:** Pre-scan all lines for `maxLen` at `openVirtualViewer` time and set `vwindow.style.minWidth` once. Removed all `scrollWidth` reads from the RAF hot path entirely.

### 7. Auto-scroll to bottom (CSS Scroll Anchoring feedback loop)

**Cause:** CSS Scroll Anchoring is enabled by default. When `start > 0`, `spacerTop.style.height` grows as the user scrolls down. The browser detects that the content above the in-viewport anchor element has grown and automatically adds the same delta to `scrollTop` to keep the anchor visually stable. This fires a new scroll event → RAF → `renderVirtualWindow` → spacerTop grows more → anchoring compensates again. The loop continues until `end = total` and `spacerBot = 0` (no more spacerTop growth possible).

**Fix:** `overflow-anchor: none` on `#viewer-body`. This is standard practice for all virtual-scroll implementations.
