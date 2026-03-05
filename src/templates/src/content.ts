/** Off-thread JSON.parse for file content, with in-memory cache. */

const WORKER_SRC = [
    "var m=null,q=[];",
    "self.onmessage=function(e){",
    "  var d=e.data;",
    '  if(d.cmd==="init"){',
    "    try{m=JSON.parse(d.json);}catch(x){m={};}",
    '    q.forEach(function(r){self.postMessage({id:r.id,c:m[r.k]||""});});',
    "    q=[];",
    '  }else if(d.cmd==="get"){',
    '    if(m!==null){self.postMessage({id:d.id,c:m[d.k]||""});}',
    "    else{q.push({id:d.id,k:d.k});}",
    "  }",
    "};",
].join("\n");

export let contentCache: Record<string, string> = {};
let contentReqId = 0;
const contentReqMap: Record<number, { key: string; cb: (s: string) => void }> = {};
let contentWorker: Worker | null = null;

function createWorker(): Worker {
    const blob = new Blob([WORKER_SRC], { type: "text/javascript" });
    const w = new Worker(URL.createObjectURL(blob));
    w.onmessage = function (e: MessageEvent<{ id: number; c: string }>) {
        const req = contentReqMap[e.data.id];
        if (!req) return;
        delete contentReqMap[e.data.id];
        contentCache[req.key] = e.data.c;
        req.cb(e.data.c);
    };
    return w;
}

export function fetchContent(path: string, cb: (s: string) => void): void {
    if (Object.prototype.hasOwnProperty.call(contentCache, path)) {
        cb(contentCache[path]);
        return;
    }
    if (!contentWorker) { cb(""); return; }
    const id = contentReqId++;
    contentReqMap[id] = { key: path, cb };
    contentWorker.postMessage({ cmd: "get", id, k: path });
}

export function initContentWorker(jsonText: string): void {
    if (contentWorker) {
        try { contentWorker.terminate(); } catch { /* ignore */ }
    }
    contentCache = {};
    Object.keys(contentReqMap).forEach((k) => delete contentReqMap[+k]);
    try {
        contentWorker = createWorker();
        contentWorker.postMessage({ cmd: "init", json: jsonText });
    } catch {
        contentWorker = null;
        try { contentCache = JSON.parse(jsonText) as Record<string, string>; }
        catch { contentCache = {}; }
    }
}
