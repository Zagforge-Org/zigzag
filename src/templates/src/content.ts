/** Lazily fetch report-content.json on first file open, with in-memory cache. */

// null = not yet attempted, false = failed, object = loaded
let _cache: Record<string, string> | null = null;
let _failed = false;
let _overrideUrl: string | null = null;

// Proactively detect file:// so users see guidance without having to click a file first.
if (location.protocol === "file:") {
    _failed = true;
    // Show banner after DOM is ready (script runs deferred, so DOM is already parsed).
    document.addEventListener("DOMContentLoaded", function () {
        const banner = document.getElementById("offline-banner");
        if (banner) banner.style.display = "block";
    }, { once: true });
    // Also try immediately in case DOMContentLoaded already fired.
    if (document.readyState !== "loading") {
        const banner = document.getElementById("offline-banner");
        if (banner) banner.style.display = "block";
    }
}

// Pending callbacks waiting for the first fetch to complete
const _pending: Array<{ path: string; cb: (s: string) => void }> = [];
let _fetching = false;

function showOfflineBanner(): void {
    const banner = document.getElementById("offline-banner");
    if (banner) banner.style.display = "block";
}

function drainPending(): void {
    while (_pending.length > 0) {
        const req = _pending.shift()!;
        if (_failed || _cache === null) {
            req.cb("");
        } else {
            req.cb(_cache[req.path] ?? "");
        }
    }
}

function resolveContentUrl(): string {
    if (_overrideUrl !== null) return _overrideUrl;
    const pageUrl = location.href.replace(/[?#].*$/, "");
    const dir = pageUrl.substring(0, pageUrl.lastIndexOf("/") + 1);
    return dir + "report-content.json";
}

function doFetch(): void {
    _fetching = true;
    fetch(resolveContentUrl(), { cache: "no-store" })
        .then(function (r) {
            if (!r.ok) throw new Error("HTTP " + r.status);
            return r.json() as Promise<Record<string, string>>;
        })
        .then(function (data) {
            _cache = data;
            _fetching = false;
            drainPending();
        })
        .catch(function (e: unknown) {
            const msg = e instanceof Error ? e.message : String(e);
            console.warn("ZigZag: failed to load report-content.json:", msg);
            _failed = true;
            showOfflineBanner();
            _fetching = false;
            drainPending();
        });
}

/** Override the URL used to fetch the content sidecar JSON (default: derived from location). */
export function setContentUrl(url: string): void {
    _overrideUrl = url;
}

export function fetchContent(path: string, cb: (s: string) => void): void {
    // Already have data
    if (_cache !== null) {
        cb(_cache[path] ?? "");
        return;
    }
    // Previously failed
    if (_failed) {
        cb("");
        return;
    }
    // file:// — fetch is blocked, show guidance immediately
    if (location.protocol === "file:") {
        showOfflineBanner();
        _failed = true;
        cb("");
        return;
    }
    // Enqueue and kick off fetch if not already in flight
    _pending.push({ path, cb });
    if (!_fetching) doFetch();
}

/** Returns true if content for the given path is already in the cache. */
export function isContentCached(path: string): boolean {
    return _cache !== null && Object.prototype.hasOwnProperty.call(_cache, path);
}

/** Replace cached content map (used by watch-mode updates). */
export function setContentCache(data: Record<string, string>): void {
    _cache = data;
    _failed = false;
    // Drain any callbacks that were waiting before the watch update arrived
    drainPending();
}

/** Update or insert a single entry in the content cache (used by delta SSE events). */
export function updateContentEntry(path: string, content: string): void {
    if (_cache === null) _cache = {};
    _cache[path] = content;
    _failed = false;
}

/** Remove a single entry from the content cache (used by file_delete delta events). */
export function removeContentEntry(path: string): void {
    if (_cache !== null) delete _cache[path];
}

/** Reset all content state (used when watch mode receives a full reload). */
export function resetContent(): void {
    _cache = null;
    _failed = false;
    _fetching = false;
    _pending.length = 0;
}
