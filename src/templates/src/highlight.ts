/** Lazy Prism highlight worker — reads source from the #prism-src element. */

let hlWorker: Worker | null = null;
let hlReqId = 0;
const hlReqMap: Record<number, (html: string) => void> = {};

function getHighlightWorker(): Worker | null {
    if (hlWorker) return hlWorker;
    const src = document.getElementById("prism-src");
    if (!src) return null;
    try {
        const blob = new Blob([src.textContent!], { type: "text/javascript" });
        hlWorker = new Worker(URL.createObjectURL(blob));
        hlWorker.onmessage = function (e: MessageEvent<{ id: number; html: string }>) {
            const cb = hlReqMap[e.data.id];
            if (!cb) return;
            delete hlReqMap[e.data.id];
            cb(e.data.html);
        };
        hlWorker.onerror = function () {
            hlWorker = null;
        };
    } catch {
        hlWorker = null;
    }
    return hlWorker;
}

export function highlightAsync(
    code: string,
    language: string,
    cb: (html: string | null) => void,
): void {
    const w = getHighlightWorker();
    if (!w) { cb(null); return; }
    const id = hlReqId++;
    hlReqMap[id] = cb;
    w.postMessage({ id, code, language });
}
