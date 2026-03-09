/** Per-file lazy content loading — fetches individual source files on demand.
 *  Files are located by FNV-1a 32-bit hash of the path (must match Zig's fnv1a32Hash). */

const _fileCache: Record<string, string> = {};
const _inflight: Record<string, boolean> = {};
const _callbacks: Record<string, Array<(s: string) => void>> = {};
let _prefix: string | null = null;
let _failed = false;

/** FNV-1a 32-bit hash over UTF-8 bytes — must match Zig's fnv1a32Hash. */
function fnv1a32(s: string): string {
    const bytes = new TextEncoder().encode(s);
    let h = 2166136261 >>> 0;
    for (const b of bytes) {
        h ^= b;
        h = Math.imul(h, 16777619) >>> 0;
    }
    return h.toString(16).padStart(8, "0");
}

function resolveFileUrl(path: string): string {
    const hash = fnv1a32(path);
    if (_prefix !== null) {
        return _prefix + "/" + hash;
    }
    const pageUrl = location.href.replace(/[?#].*$/, "");
    const dir = pageUrl.substring(0, pageUrl.lastIndexOf("/") + 1);
    return dir + "report-content/" + hash;
}

function showOfflineBanner(): void {
    const banner = document.getElementById("offline-banner");
    if (banner) banner.style.display = "block";
}

// Proactively detect file:// so users see guidance without clicking a file first.
if (location.protocol === "file:") {
    _failed = true;
    document.addEventListener("DOMContentLoaded", function () {
        const banner = document.getElementById("offline-banner");
        if (banner) banner.style.display = "block";
    }, { once: true });
    if (document.readyState !== "loading") {
        const banner = document.getElementById("offline-banner");
        if (banner) banner.style.display = "block";
    }
}

/** Set the content directory URL prefix (e.g. "combined-content" for combined dashboard). */
export function setContentPrefix(prefix: string): void {
    _prefix = prefix;
}

export function fetchContent(path: string, cb: (s: string) => void): void {
    if (path in _fileCache) { cb(_fileCache[path]); return; }
    if (_failed) { cb(""); return; }
    if (location.protocol === "file:") {
        showOfflineBanner();
        _failed = true;
        cb("");
        return;
    }
    // Coalesce concurrent requests for the same path
    if (!(path in _callbacks)) _callbacks[path] = [];
    _callbacks[path].push(cb);
    if (_inflight[path]) return;
    _inflight[path] = true;

    fetch(resolveFileUrl(path), { cache: "default" })
        .then(function (r) {
            if (!r.ok) throw new Error("HTTP " + r.status);
            return r.text();
        })
        .then(function (text) {
            _fileCache[path] = text;
            delete _inflight[path];
            const cbs = _callbacks[path] ?? [];
            delete _callbacks[path];
            cbs.forEach(function (f) { f(text); });
        })
        .catch(function (e: unknown) {
            console.warn("ZigZag: content fetch failed for", path, ":", e instanceof Error ? e.message : e);
            _fileCache[path] = "";
            delete _inflight[path];
            const cbs = _callbacks[path] ?? [];
            delete _callbacks[path];
            cbs.forEach(function (f) { f(""); });
            showOfflineBanner();
        });
}

export function isContentCached(path: string): boolean {
    return path in _fileCache;
}

/** Merge content into cache (used by watch mode delta events). */
export function setContentCache(data: Record<string, string>): void {
    Object.assign(_fileCache, data);
    _failed = false;
}

export function updateContentEntry(path: string, content: string): void {
    _fileCache[path] = content;
}

export function removeContentEntry(path: string): void {
    delete _fileCache[path];
}

/** Clear all content state (called on watch-mode reload). */
export function resetContent(): void {
    for (const k in _fileCache) delete _fileCache[k];
    for (const k in _inflight) delete _inflight[k];
    for (const k in _callbacks) {
        (_callbacks[k] ?? []).forEach(function (f) { f(""); });
        delete _callbacks[k];
    }
    _failed = false;
}

/** Evict cached content so files are re-fetched on next click (watch mode change). */
export function invalidateContent(): void {
    for (const k in _fileCache) delete _fileCache[k];
    _failed = false;
}
