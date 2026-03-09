import { PRISM_MAP, VIRT_LINE_THRESHOLD, VIRT_BYTE_THRESHOLD, VIEWER_LINE_HEIGHT, VIEWER_OVERSCAN, HL_CHUNK_SIZE, DISPLAY_TRUNCATE_AT, MINIFIED_LINE_THRESHOLD, MINIFIED_FILE_THRESHOLD, MINIFIED_DISPLAY_CHARS } from "./constants";
import { esc } from "./utils";
import { fetchContent } from "./content";
import { highlightAsync } from "./highlight";
import type { ReportFile } from "./types";

// ── DOM refs ──────────────────────────────────────────────────────────────────

const viewer = document.getElementById("viewer")!;
const vpathEl = document.getElementById("viewer-path")!;

// ── Viewer state ──────────────────────────────────────────────────────────────

export let currentFile: ReportFile | null = null;
let viewerToken = 0;

let virtLines: string[] | null = null;
let virtLangKey: string | null = null;
let virtBodyEl: HTMLElement | null = null;
let virtWindowEl: HTMLElement | null = null;
let virtSpacerTopEl: HTMLElement | null = null;
let virtSpacerBotEl: HTMLElement | null = null;
let virtGutterW = "3ch";
let virtRafPending = false;
let virtLastScrollTop = -1;
let hlChunkCache: Record<number, string[]> = {};
let hlChunkPending: Record<number, boolean> = {};

// ── Minified-file detection ────────────────────────────────────────────────────

function isMinifiedFile(lines: string[], rawLen: number): boolean {
    if (lines.length <= 5 && rawLen > MINIFIED_FILE_THRESHOLD) return true;
    for (let i = 0; i < lines.length; i++) {
        if (lines[i].length > MINIFIED_LINE_THRESHOLD) return true;
    }
    return false;
}

function openMinifiedViewer(rawContent: string, scrollTo = 0): void {
    const body = document.getElementById("viewer-body")!;
    const preview = esc(rawContent.slice(0, MINIFIED_DISPLAY_CHARS));
    const remaining = rawContent.length - MINIFIED_DISPLAY_CHARS;
    body.innerHTML =
        '<div class="minified-banner">' +
        "This file appears to be minified or machine-generated. " +
        "Showing first " + MINIFIED_DISPLAY_CHARS.toLocaleString() + " characters." +
        "</div>" +
        '<pre class="minified-preview">' + preview + "</pre>" +
        (remaining > 0
            ? '<div class="minified-more">\u2026 ' + remaining.toLocaleString() + " more characters not shown</div>"
            : "");
    body.scrollTop = scrollTo;
}

// ── Truncation helper ─────────────────────────────────────────────────────────

function truncateBadge(line: string): string {
    const over = line.length - DISPLAY_TRUNCATE_AT;
    return over > 0
        ? '<span class="truncate-badge">+' + over.toLocaleString() + "\u00a0chars</span>"
        : "";
}

// ── Simple viewer ─────────────────────────────────────────────────────────────

function openSimpleViewer(lines: string[], langKey: string | null, myToken: number, scrollTo = 0): void {
    const body = document.getElementById("viewer-body")!;
    const numWidth = "calc(" + String(lines.length).length + "ch + 2rem)";
    const rows: string[] = [];
    for (let i = 0; i < lines.length; i++) {
        const display = lines[i].length > DISPLAY_TRUNCATE_AT ? lines[i].slice(0, DISPLAY_TRUNCATE_AT) : lines[i];
        rows.push(
            '<tr><td class="ln" style="min-width:' +
                numWidth +
                '">' +
                (i + 1) +
                '</td><td class="lc" data-line="' +
                i +
                '">' +
                esc(display) +
                truncateBadge(lines[i]) +
                "</td></tr>",
        );
    }
    body.innerHTML =
        '<table class="ln-table"><tbody>' + rows.join("") + "</tbody></table>";
    body.scrollTop = scrollTo;

    if (!langKey) return;

    // Highlight the truncated version of each line so token boundaries stay valid.
    const truncatedContent = lines
        .map(function (l) { return l.length > DISPLAY_TRUNCATE_AT ? l.slice(0, DISPLAY_TRUNCATE_AT) : l; })
        .join("\n");
    highlightAsync(truncatedContent, langKey, function (highlighted) {
        if (viewerToken !== myToken) return;
        if (!highlighted) return;
        const hlLines = highlighted.split("\n");
        const cells = body.querySelectorAll<HTMLElement>("td.lc[data-line]");
        for (let j = 0; j < cells.length; j++) {
            const idx = parseInt(cells[j].dataset.line!, 10);
            if (hlLines[idx] !== undefined) cells[j].innerHTML = hlLines[idx] + truncateBadge(lines[idx]);
        }
    });
}

// ── Virtual viewer ────────────────────────────────────────────────────────────

function scheduleVirtualViewerRender(): void {
    if (virtRafPending || !virtLines) return;
    virtRafPending = true;
    requestAnimationFrame(function () {
        virtRafPending = false;
        if (virtLines) renderVirtualWindow();
    });
}

function renderVirtualWindow(): void {
    if (!virtLines || !virtBodyEl || !virtWindowEl) return;
    const total = virtLines.length;
    const scrollTop = virtBodyEl.scrollTop;

    if (scrollTop === virtLastScrollTop) return;
    virtLastScrollTop = scrollTop;

    const viewH = virtBodyEl.clientHeight;

    const start = Math.max(0, Math.floor(scrollTop / VIEWER_LINE_HEIGHT) - VIEWER_OVERSCAN);
    const end = Math.min(
        total,
        Math.ceil((scrollTop + viewH) / VIEWER_LINE_HEIGHT) + VIEWER_OVERSCAN,
    );

    virtWindowEl.style.height = (end - start) * VIEWER_LINE_HEIGHT + "px";
    virtSpacerTopEl!.style.height = start * VIEWER_LINE_HEIGHT + "px";
    virtSpacerBotEl!.style.height = (total - end) * VIEWER_LINE_HEIGHT + "px";

    const frag = document.createDocumentFragment();
    for (let i = start; i < end; i++) {
        const row = document.createElement("div");
        row.className = "vline";

        const ln = document.createElement("span");
        ln.className = "ln";
        ln.style.width = virtGutterW;
        ln.textContent = String(i + 1);

        const lc = document.createElement("span");
        lc.className = "lc";
        lc.dataset.line = String(i);

        const chunkIdx = Math.floor(i / HL_CHUNK_SIZE);
        const lineInChunk = i - chunkIdx * HL_CHUNK_SIZE;
        if (hlChunkCache[chunkIdx] && hlChunkCache[chunkIdx][lineInChunk] !== undefined) {
            lc.innerHTML = hlChunkCache[chunkIdx][lineInChunk] + truncateBadge(virtLines[i]);
        } else {
            const display = virtLines[i].length > DISPLAY_TRUNCATE_AT ? virtLines[i].slice(0, DISPLAY_TRUNCATE_AT) : virtLines[i];
            lc.innerHTML = esc(display) + truncateBadge(virtLines[i]);
        }

        row.appendChild(ln);
        row.appendChild(lc);
        frag.appendChild(row);
    }

    virtWindowEl.innerHTML = "";
    virtWindowEl.appendChild(frag);

    if (virtLangKey) requestVisibleChunks(start, end, viewerToken);
}

function requestVisibleChunks(start: number, end: number, token: number): void {
    if (!virtLines || !virtLangKey) return;
    const firstChunk = Math.floor(start / HL_CHUNK_SIZE);
    const lastChunk = Math.floor(Math.max(start, end - 1) / HL_CHUNK_SIZE);

    for (let c = firstChunk; c <= lastChunk; c++) {
        if (hlChunkCache[c] || hlChunkPending[c]) continue;
        hlChunkPending[c] = true;
        (function (chunkIdx: number, myToken: number) {
            const chunkStart = chunkIdx * HL_CHUNK_SIZE;
            const chunkEnd = Math.min(virtLines!.length, chunkStart + HL_CHUNK_SIZE);
            const chunkText = virtLines!.slice(chunkStart, chunkEnd)
                    .map(function (l) { return l.length > DISPLAY_TRUNCATE_AT ? l.slice(0, DISPLAY_TRUNCATE_AT) : l; })
                    .join("\n");

            highlightAsync(chunkText, virtLangKey!, function (html) {
                if (viewerToken !== myToken || !virtLines) return;
                delete hlChunkPending[chunkIdx];
                if (!html) return;

                const hlLines = html.split("\n");
                hlChunkCache[chunkIdx] = hlLines;

                if (!virtWindowEl) return;
                const cells = virtWindowEl.querySelectorAll<HTMLElement>(".lc[data-line]");
                for (let j = 0; j < cells.length; j++) {
                    const lineIdx = parseInt(cells[j].dataset.line!, 10);
                    if (Math.floor(lineIdx / HL_CHUNK_SIZE) !== chunkIdx) continue;
                    const lineInChunk = lineIdx - chunkStart;
                    cells[j].innerHTML =
                        hlLines[lineInChunk] !== undefined
                            ? hlLines[lineInChunk] + truncateBadge(virtLines![lineIdx])
                            : esc(virtLines![lineIdx].length > DISPLAY_TRUNCATE_AT ? virtLines![lineIdx].slice(0, DISPLAY_TRUNCATE_AT) : virtLines![lineIdx]) + truncateBadge(virtLines![lineIdx]);
                }
            });
        })(c, token);
    }
}

function openVirtualViewer(lines: string[], langKey: string | null, myToken: number, scrollTo = 0): void {
    virtLines = lines;
    virtLangKey = langKey;
    virtLastScrollTop = -1;

    const digits = String(lines.length).length;
    virtGutterW = "calc(" + digits + "ch + 2rem)";

    let maxLen = 0;
    for (let mi = 0; mi < lines.length; mi++) {
        // Cap at DISPLAY_TRUNCATE_AT — that's the most we actually render per line.
        const len = Math.min(lines[mi].length, DISPLAY_TRUNCATE_AT);
        if (len > maxLen) maxLen = len;
    }

    const body = document.getElementById("viewer-body")!;
    body.innerHTML = "";
    virtBodyEl = body;

    const spacerTop = document.createElement("div");
    const win = document.createElement("div");
    win.className = "vwindow";
    win.style.minWidth = "calc(" + (digits + maxLen) + "ch + 3rem)";
    const spacerBot = document.createElement("div");

    body.appendChild(spacerTop);
    body.appendChild(win);
    body.appendChild(spacerBot);

    virtSpacerTopEl = spacerTop;
    virtWindowEl = win;
    virtSpacerBotEl = spacerBot;

    // Pre-size spacerTop so the browser honours the requested scrollTop,
    // then let renderVirtualWindow() recompute the correct spacer heights.
    if (scrollTo > 0) {
        spacerTop.style.height = scrollTo + "px";
        body.scrollTop = scrollTo;
    }

    body.addEventListener("scroll", scheduleVirtualViewerRender);
    renderVirtualWindow();
}

// ── Public API ────────────────────────────────────────────────────────────────

export function openViewer(f: ReportFile, preserveScroll = false): void {
    const body = document.getElementById("viewer-body")!;
    const sameFile = preserveScroll && currentFile !== null && currentFile.path === f.path;
    const savedScrollTop = sameFile ? body.scrollTop : 0;

    currentFile = f;
    viewerToken++;
    const myToken = viewerToken;

    virtLines = null;
    virtLangKey = null;
    virtRafPending = false;
    virtLastScrollTop = -1;
    hlChunkCache = {};
    hlChunkPending = {};
    if (virtBodyEl) {
        virtBodyEl.removeEventListener("scroll", scheduleVirtualViewerRender);
        virtBodyEl = null;
    }
    virtWindowEl = null;
    virtSpacerTopEl = null;
    virtSpacerBotEl = null;

    vpathEl.textContent = f.path;
    viewer.classList.add("open");

    // Only show the loading placeholder when opening a different file.
    // When the same file is refreshed (watch update), keep the existing
    // content visible until the new content is ready.
    if (!sameFile) {
        body.innerHTML =
            '<div style="padding:0.75rem 1rem;color:#adb5bd;font-size:0.8rem">Loading\u2026</div>';
        body.scrollTop = 0;
    }

    fetchContent(f.path, function (raw) {
        if (viewerToken !== myToken) return;
        const rawContent = (raw || "(binary or empty)").replace(/\r\n/g, "\n").replace(/\r/g, "\n");
        const lines = rawContent.split("\n");
        const langKey = PRISM_MAP[f.language || ""] || null;

        if (isMinifiedFile(lines, rawContent.length)) {
            openMinifiedViewer(rawContent, savedScrollTop);
        } else if (lines.length > VIRT_LINE_THRESHOLD || rawContent.length > VIRT_BYTE_THRESHOLD) {
            openVirtualViewer(lines, langKey, myToken, savedScrollTop);
        } else {
            openSimpleViewer(lines, langKey, myToken, savedScrollTop);
        }
    });
}

export function closeViewer(): void {
    viewer.classList.remove("open");
    currentFile = null;
    viewerToken++;

    virtLines = null;
    virtLangKey = null;
    virtRafPending = false;
    virtLastScrollTop = -1;
    hlChunkCache = {};
    hlChunkPending = {};
    if (virtBodyEl) {
        virtBodyEl.removeEventListener("scroll", scheduleVirtualViewerRender);
        virtBodyEl = null;
    }
    virtWindowEl = null;
    virtSpacerTopEl = null;
    virtSpacerBotEl = null;
}

// ── Keyboard / close button ───────────────────────────────────────────────────

document.getElementById("viewer-close")!.addEventListener("click", closeViewer);
document.addEventListener("keydown", function (e) {
    if (e.key === "Escape") closeViewer();
});
