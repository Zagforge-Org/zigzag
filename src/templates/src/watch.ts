import { M, setReport } from "./state";
import { setContentCache, resetContent } from "./content";
import { renderHeader, renderCards } from "./header";
import { renderLangChart, renderSizeChart } from "./charts";
import { renderTable } from "./table";
import { openViewer, closeViewer, currentFile } from "./viewer";
import type { Report } from "./types";

function extractReport(html: string): Report | null {
    const m = /id="rpt"[^>]*>([\s\S]*?)<\/script>/i.exec(html);
    if (!m) return null;
    try { return JSON.parse(m[1]) as Report; } catch { return null; }
}

export function softUpdate(newR: Report, newContent: Record<string, string> | null): void {
    setReport(newR);
    if (newContent !== null) {
        setContentCache(newContent);
    }
    renderHeader();
    renderCards();
    renderLangChart();
    renderSizeChart();
    renderTable();

    if (currentFile !== null) {
        const updated = newR.files.find((f) => f.path === currentFile!.path) ?? null;
        if (updated) openViewer(updated);
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
                // Fetch fresh report data and content sidecar in parallel
                return Promise.all([
                    fetch(location.href, { cache: "no-store" }).then((r) => r.text()),
                    fetch(resolveContentUrl(), { cache: "no-store" })
                        .then((r) => r.ok ? r.json() as Promise<Record<string, string>> : Promise.resolve(null))
                        .catch(() => null),
                ]).then(function ([html, content]) {
                    const newR = extractReport(html);
                    if (newR) softUpdate(newR, content);
                });
            })
            .catch(function () {})
            .then(function () { setTimeout(poll, 2000); });
    }
    setTimeout(poll, 2000);
}

function resolveContentUrl(): string {
    const pageUrl = location.href.replace(/[?#].*$/, "");
    const dir = pageUrl.substring(0, pageUrl.lastIndexOf("/") + 1);
    return dir + "report-content.json";
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
            const msg = JSON.parse(e.data) as { report: Report; content: Record<string, string> | null };
            if (msg.report) softUpdate(msg.report, msg.content ?? null);
        } catch { /* ignore malformed messages */ }
    });

    // Named event: server requests a full page reload (e.g. template changed).
    es.addEventListener("reload", function () {
        received = true;
        resetContent();
        location.reload();
    });

    es.onerror = function () {
        if (!received) {
            // Never got a message — server is likely not running.
            es.close();
            startPolling();
        }
        // If we already received events, let EventSource auto-reconnect
        // (browser retries after the `retry:` interval set by the server).
    };
}
