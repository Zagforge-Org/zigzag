import { M, F, setReport } from "./state";
import { setContentCache, resetContent, updateContentEntry, removeContentEntry, invalidateContent } from "./content";
import { renderHeader, renderCards } from "./header";
import { renderLangChart, renderSizeChart } from "./charts";
import { renderTable, getTotalCount, scrollToFile } from "./table";
import { openViewer, closeViewer, currentFile } from "./viewer";
import type { Report, ReportFile } from "./types";

function extractReport(html: string): Report | null {
    const m = /id="rpt"[^>]*>([\s\S]*?)<\/script>/i.exec(html);
    if (!m) return null;
    try { return JSON.parse(m[1]) as Report; } catch { return null; }
}

function updateCountBadge(): void {
    const el = document.getElementById("search-count");
    if (el) el.textContent = getTotalCount() + " files";
}

export function softUpdate(newR: Report, newContent: Record<string, string> | null): void {
    setReport(newR);
    if (newContent !== null) {
        setContentCache(newContent);
    } else {
        // Full update (no inline content): sidecars on disk are up-to-date.
        // Invalidate the in-memory cache so the viewer re-fetches fresh content.
        invalidateContent();
    }
    renderHeader();
    renderCards();
    renderLangChart();
    renderSizeChart();
    renderTable(false);
    updateCountBadge();

    if (currentFile !== null) {
        const updated = newR.files.find((f) => f.path === currentFile!.path) ?? null;
        if (updated) openViewer(updated, true);
        else closeViewer();
    }
}

function startPolling(): void {
    function poll(): void {
        const stampUrl = location.href + ".stamp";
        fetch(stampUrl, { cache: "no-store" })
            .then(function (r) { return r.ok ? r.text() : Promise.resolve<string | null>(null); })
            .then(function (ts) {
                if (!ts || ts.trim() === M.generated_at) return;
                return fetch(location.href, { cache: "no-store" })
                    .then((r) => r.text())
                    .then(function (html) {
                        const newR = extractReport(html);
                        if (newR) {
                            invalidateContent();
                            softUpdate(newR, null);
                        }
                    });
            })
            .catch(function () {})
            .then(function () { setTimeout(poll, 2000); });
    }
    setTimeout(poll, 2000);
}

function setSseDot(state: "live" | "reconnecting"): void {
    const dot = document.getElementById("sse-dot") as HTMLElement | null;
    if (!dot) return;
    dot.style.display = "block";
    dot.classList.toggle("reconnecting", state === "reconnecting");
    dot.title = state === "live" ? "Watch: live" : "Watch: reconnecting…";
}

export function startWatchMode(): void {
    if (typeof EventSource === "undefined") {
        startPolling();
        return;
    }

    // Prefer the absolute SSE URL embedded at generation time (works when the
    // HTML is opened from disk). Fall back to the relative path when served
    // directly by the SSE server on the same origin.
    const sseUrl = M.sse_url ?? "/__events";

    let es: EventSource;
    try {
        es = new EventSource(sseUrl);
        setSseDot("live");
    } catch {
        startPolling();
        return;
    }

    // Track whether we ever received a server event. If not and the connection
    // errors, the server is not running — fall back to stamp polling.
    let received = false;

    // Named event: server pushes updated report data.
    es.addEventListener("report", function (e: MessageEvent<string>) {
        received = true;
        try {
            const msg = JSON.parse(e.data) as {
                type?: string;
                report?: Report;
                content?: Record<string, string> | null;
                path?: string;
                meta?: { size: number; lines: number; language: string };
            };

            // Delta: single file was updated or created
            if (msg.type === "file_update" && msg.path !== undefined) {
                if ("content" in msg && typeof (msg as Record<string, unknown>).content === "string") {
                    const c = (msg as unknown as { content: string }).content;
                    updateContentEntry(msg.path, c);
                }
                let isNew = false;
                if (msg.meta) {
                    const existing = F.findIndex((f) => f.path === msg.path);
                    isNew = existing < 0;
                    const updated: ReportFile = {
                        path: msg.path,
                        size: msg.meta.size,
                        lines: msg.meta.lines,
                        language: msg.meta.language,
                    };
                    if (existing >= 0) {
                        F[existing] = updated;
                    } else {
                        F.push(updated);
                    }
                }
                renderTable(false);
                updateCountBadge();
                if (isNew) scrollToFile(msg.path);
                if (currentFile?.path === msg.path) {
                    const fileEntry = F.find((f) => f.path === msg.path);
                    if (fileEntry) openViewer(fileEntry, true);
                }
                return;
            }

            // Delta: single file was deleted
            if (msg.type === "file_delete" && msg.path !== undefined) {
                removeContentEntry(msg.path);
                const idx = F.findIndex((f) => f.path === msg.path);
                if (idx >= 0) F.splice(idx, 1);
                renderTable(false);
                updateCountBadge();
                if (currentFile?.path === msg.path) closeViewer();
                return;
            }

            // Full update (initial or legacy)
            if (msg.report) {
                const prevPaths = new Set(F.map((f) => f.path));
                softUpdate(msg.report, msg.content ?? null);
                // Scroll to the first newly-added file (covers the case where the
                // delta was lost or the file was empty when IN_CREATE fired).
                const firstNew = msg.report.files.find((f) => !prevPaths.has(f.path));
                if (firstNew) scrollToFile(firstNew.path);
            }
        } catch { /* ignore malformed messages */ }
    });

    // Named event: server requests a full page reload (e.g. template changed).
    es.addEventListener("reload", function () {
        received = true;
        resetContent();
        location.reload();
    });

    es.onopen = () => setSseDot("live");

    es.onerror = function () {
        if (!received) {
            // Never got a message — server is likely not running.
            es.close();
            startPolling();
        } else {
            setSseDot("reconnecting");
        }
        // If we already received events, let EventSource auto-reconnect
        // (browser retries after the `retry:` interval set by the server).
    };
}
