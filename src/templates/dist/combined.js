"use strict";
(() => {
  // src/content.ts
  var _cache = null;
  var _failed = false;
  var _pending = [];
  var _fetching = false;
  function showOfflineBanner() {
    const banner = document.getElementById("offline-banner");
    if (banner) banner.style.display = "block";
  }
  function drainPending() {
    while (_pending.length > 0) {
      const req = _pending.shift();
      if (_failed || _cache === null) {
        req.cb("");
      } else {
        req.cb(_cache[req.path] ?? "");
      }
    }
  }
  function resolveContentUrl() {
    const pageUrl = location.href.replace(/[?#].*$/, "");
    const dir = pageUrl.substring(0, pageUrl.lastIndexOf("/") + 1);
    return dir + "report-content.json";
  }
  function doFetch() {
    _fetching = true;
    fetch(resolveContentUrl(), { cache: "no-store" }).then(function(r) {
      if (!r.ok) throw new Error("HTTP " + r.status);
      return r.json();
    }).then(function(data) {
      _cache = data;
      _fetching = false;
      drainPending();
    }).catch(function(e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.warn("ZigZag: failed to load report-content.json:", msg);
      _failed = true;
      showOfflineBanner();
      _fetching = false;
      drainPending();
    });
  }
  function fetchContent(path, cb) {
    if (_cache !== null) {
      cb(_cache[path] ?? "");
      return;
    }
    if (_failed) {
      cb("");
      return;
    }
    if (location.protocol === "file:") {
      showOfflineBanner();
      _failed = true;
      cb("");
      return;
    }
    _pending.push({ path, cb });
    if (!_fetching) doFetch();
  }
  function updateContentEntry(path, content) {
    if (_cache === null) _cache = {};
    _cache[path] = content;
    _failed = false;
  }

  // src/constants.ts
  var VIRT_LINE_THRESHOLD = 500;
  var VIRT_BYTE_THRESHOLD = 200 * 1024;
  var VIEWER_LINE_HEIGHT = 20;
  var VIEWER_OVERSCAN = 15;
  var HL_CHUNK_SIZE = 200;
  var DISPLAY_TRUNCATE_AT = 2e3;
  var MINIFIED_LINE_THRESHOLD = 1e4;
  var MINIFIED_FILE_THRESHOLD = 5e4;
  var MINIFIED_DISPLAY_CHARS = 1e4;
  var PRISM_MAP = {
    zig: "zig",
    js: "javascript",
    javascript: "javascript",
    mjs: "javascript",
    cjs: "javascript",
    jsx: "jsx",
    lua: "lua",
    ts: "typescript",
    typescript: "typescript",
    tsx: "tsx",
    json: "json",
    html: "markup",
    htm: "markup",
    xml: "markup",
    svg: "markup",
    vue: "markup",
    svelte: "markup",
    astro: "markup",
    css: "css",
    scss: "scss",
    less: "less",
    bash: "bash",
    sh: "bash",
    zsh: "bash",
    c: "c",
    h: "c",
    cpp: "cpp",
    hpp: "cpp",
    cc: "cpp",
    cxx: "cpp",
    hh: "cpp",
    rs: "rust",
    go: "go",
    mod: "go",
    py: "python",
    pyw: "python",
    pyi: "python",
    rb: "ruby",
    java: "java",
    kt: "kotlin",
    kts: "kotlin",
    groovy: "groovy",
    scala: "scala",
    cs: "csharp",
    fs: "fsharp",
    vb: "vbnet",
    php: "php",
    swift: "swift",
    dart: "dart",
    jl: "julia",
    hs: "haskell",
    elm: "elm",
    clj: "clojure",
    ex: "elixir",
    exs: "elixir",
    erl: "erlang",
    md: "markdown",
    toml: "toml",
    yaml: "yaml",
    yml: "yaml",
    sql: "sql"
  };

  // src/utils.ts
  function fmt(n) {
    if (n >= 1073741824) return (n / 1073741824).toFixed(1) + " GB";
    if (n >= 1048576) return (n / 1048576).toFixed(1) + " MB";
    if (n >= 1024) return (n / 1024).toFixed(1) + " KB";
    return n + " B";
  }
  function esc(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }

  // src/highlight.ts
  var hlWorker = null;
  var hlReqId = 0;
  var hlReqMap = {};
  function getHighlightWorker() {
    if (hlWorker) return hlWorker;
    const src = document.getElementById("prism-src");
    if (!src) return null;
    try {
      const blob = new Blob([src.textContent], { type: "text/javascript" });
      hlWorker = new Worker(URL.createObjectURL(blob));
      hlWorker.onmessage = function(e) {
        const cb = hlReqMap[e.data.id];
        if (!cb) return;
        delete hlReqMap[e.data.id];
        cb(e.data.html);
      };
      hlWorker.onerror = function() {
        hlWorker = null;
      };
    } catch {
      hlWorker = null;
    }
    return hlWorker;
  }
  function highlightAsync(code, language, cb) {
    const w = getHighlightWorker();
    if (!w) {
      cb(null);
      return;
    }
    const id = hlReqId++;
    hlReqMap[id] = cb;
    w.postMessage({ id, code, language });
  }

  // src/viewer.ts
  var viewer = document.getElementById("viewer");
  var vpathEl = document.getElementById("viewer-path");
  var currentFile = null;
  var viewerToken = 0;
  var virtLines = null;
  var virtLangKey = null;
  var virtBodyEl = null;
  var virtWindowEl = null;
  var virtSpacerTopEl = null;
  var virtSpacerBotEl = null;
  var virtGutterW = "3ch";
  var virtRafPending = false;
  var virtLastScrollTop = -1;
  var hlChunkCache = {};
  var hlChunkPending = {};
  function isMinifiedFile(lines, rawLen) {
    if (lines.length <= 5 && rawLen > MINIFIED_FILE_THRESHOLD) return true;
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].length > MINIFIED_LINE_THRESHOLD) return true;
    }
    return false;
  }
  function openMinifiedViewer(rawContent) {
    const body = document.getElementById("viewer-body");
    const preview = esc(rawContent.slice(0, MINIFIED_DISPLAY_CHARS));
    const remaining = rawContent.length - MINIFIED_DISPLAY_CHARS;
    body.innerHTML = '<div class="minified-banner">This file appears to be minified or machine-generated. Showing first ' + MINIFIED_DISPLAY_CHARS.toLocaleString() + ' characters.</div><pre class="minified-preview">' + preview + "</pre>" + (remaining > 0 ? '<div class="minified-more">\u2026 ' + remaining.toLocaleString() + " more characters not shown</div>" : "");
    body.scrollTop = 0;
  }
  function truncateBadge(line) {
    const over = line.length - DISPLAY_TRUNCATE_AT;
    return over > 0 ? '<span class="truncate-badge">+' + over.toLocaleString() + "\xA0chars</span>" : "";
  }
  function openSimpleViewer(lines, langKey, myToken) {
    const body = document.getElementById("viewer-body");
    const numWidth = "calc(" + String(lines.length).length + "ch + 2rem)";
    const rows = [];
    for (let i = 0; i < lines.length; i++) {
      const display = lines[i].length > DISPLAY_TRUNCATE_AT ? lines[i].slice(0, DISPLAY_TRUNCATE_AT) : lines[i];
      rows.push(
        '<tr><td class="ln" style="min-width:' + numWidth + '">' + (i + 1) + '</td><td class="lc" data-line="' + i + '">' + esc(display) + truncateBadge(lines[i]) + "</td></tr>"
      );
    }
    body.innerHTML = '<table class="ln-table"><tbody>' + rows.join("") + "</tbody></table>";
    body.scrollTop = 0;
    if (!langKey) return;
    const truncatedContent = lines.map(function(l) {
      return l.length > DISPLAY_TRUNCATE_AT ? l.slice(0, DISPLAY_TRUNCATE_AT) : l;
    }).join("\n");
    highlightAsync(truncatedContent, langKey, function(highlighted) {
      if (viewerToken !== myToken) return;
      if (!highlighted) return;
      const hlLines = highlighted.split("\n");
      const cells = body.querySelectorAll("td.lc[data-line]");
      for (let j = 0; j < cells.length; j++) {
        const idx = parseInt(cells[j].dataset.line, 10);
        if (hlLines[idx] !== void 0) cells[j].innerHTML = hlLines[idx] + truncateBadge(lines[idx]);
      }
    });
  }
  function scheduleVirtualViewerRender() {
    if (virtRafPending || !virtLines) return;
    virtRafPending = true;
    requestAnimationFrame(function() {
      virtRafPending = false;
      if (virtLines) renderVirtualWindow();
    });
  }
  function renderVirtualWindow() {
    if (!virtLines || !virtBodyEl || !virtWindowEl) return;
    const total = virtLines.length;
    const scrollTop = virtBodyEl.scrollTop;
    if (scrollTop === virtLastScrollTop) return;
    virtLastScrollTop = scrollTop;
    const viewH = virtBodyEl.clientHeight;
    const start = Math.max(0, Math.floor(scrollTop / VIEWER_LINE_HEIGHT) - VIEWER_OVERSCAN);
    const end = Math.min(
      total,
      Math.ceil((scrollTop + viewH) / VIEWER_LINE_HEIGHT) + VIEWER_OVERSCAN
    );
    virtWindowEl.style.height = (end - start) * VIEWER_LINE_HEIGHT + "px";
    virtSpacerTopEl.style.height = start * VIEWER_LINE_HEIGHT + "px";
    virtSpacerBotEl.style.height = (total - end) * VIEWER_LINE_HEIGHT + "px";
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
      if (hlChunkCache[chunkIdx] && hlChunkCache[chunkIdx][lineInChunk] !== void 0) {
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
  function requestVisibleChunks(start, end, token) {
    if (!virtLines || !virtLangKey) return;
    const firstChunk = Math.floor(start / HL_CHUNK_SIZE);
    const lastChunk = Math.floor(Math.max(start, end - 1) / HL_CHUNK_SIZE);
    for (let c = firstChunk; c <= lastChunk; c++) {
      if (hlChunkCache[c] || hlChunkPending[c]) continue;
      hlChunkPending[c] = true;
      (function(chunkIdx, myToken) {
        const chunkStart = chunkIdx * HL_CHUNK_SIZE;
        const chunkEnd = Math.min(virtLines.length, chunkStart + HL_CHUNK_SIZE);
        const chunkText = virtLines.slice(chunkStart, chunkEnd).map(function(l) {
          return l.length > DISPLAY_TRUNCATE_AT ? l.slice(0, DISPLAY_TRUNCATE_AT) : l;
        }).join("\n");
        highlightAsync(chunkText, virtLangKey, function(html) {
          if (viewerToken !== myToken || !virtLines) return;
          delete hlChunkPending[chunkIdx];
          if (!html) return;
          const hlLines = html.split("\n");
          hlChunkCache[chunkIdx] = hlLines;
          if (!virtWindowEl) return;
          const cells = virtWindowEl.querySelectorAll(".lc[data-line]");
          for (let j = 0; j < cells.length; j++) {
            const lineIdx = parseInt(cells[j].dataset.line, 10);
            if (Math.floor(lineIdx / HL_CHUNK_SIZE) !== chunkIdx) continue;
            const lineInChunk = lineIdx - chunkStart;
            cells[j].innerHTML = hlLines[lineInChunk] !== void 0 ? hlLines[lineInChunk] + truncateBadge(virtLines[lineIdx]) : esc(virtLines[lineIdx].length > DISPLAY_TRUNCATE_AT ? virtLines[lineIdx].slice(0, DISPLAY_TRUNCATE_AT) : virtLines[lineIdx]) + truncateBadge(virtLines[lineIdx]);
          }
        });
      })(c, token);
    }
  }
  function openVirtualViewer(lines, langKey, myToken) {
    virtLines = lines;
    virtLangKey = langKey;
    virtLastScrollTop = -1;
    const digits = String(lines.length).length;
    virtGutterW = "calc(" + digits + "ch + 2rem)";
    let maxLen = 0;
    for (let mi = 0; mi < lines.length; mi++) {
      const len = Math.min(lines[mi].length, DISPLAY_TRUNCATE_AT);
      if (len > maxLen) maxLen = len;
    }
    const body = document.getElementById("viewer-body");
    body.innerHTML = "";
    body.scrollTop = 0;
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
    body.addEventListener("scroll", scheduleVirtualViewerRender);
    renderVirtualWindow();
  }
  function openViewer(f) {
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
    const body = document.getElementById("viewer-body");
    body.innerHTML = '<div style="padding:0.75rem 1rem;color:#adb5bd;font-size:0.8rem">Loading\u2026</div>';
    body.scrollTop = 0;
    fetchContent(f.path, function(raw) {
      if (viewerToken !== myToken) return;
      const rawContent = (raw || "(binary or empty)").replace(/\r\n/g, "\n").replace(/\r/g, "\n");
      const lines = rawContent.split("\n");
      const langKey = PRISM_MAP[f.language || ""] || null;
      if (isMinifiedFile(lines, rawContent.length)) {
        openMinifiedViewer(rawContent);
      } else if (lines.length > VIRT_LINE_THRESHOLD || rawContent.length > VIRT_BYTE_THRESHOLD) {
        openVirtualViewer(lines, langKey, myToken);
      } else {
        openSimpleViewer(lines, langKey, myToken);
      }
    });
  }
  function closeViewer() {
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
  document.getElementById("viewer-close").addEventListener("click", closeViewer);
  document.addEventListener("keydown", function(e) {
    if (e.key === "Escape") closeViewer();
  });

  // src/combined.ts
  var R = window.COMBINED_REPORT;
  var M = R.meta;
  var S = R.summary;
  function renderGlobalSummary() {
    const cards = document.getElementById("cards");
    const items = [
      { label: "Paths", value: String(M.path_count) },
      { label: "Source Files", value: String(S.source_files) },
      { label: "Binary Files", value: String(S.binary_files) },
      { label: "Total Lines", value: S.total_lines.toLocaleString() },
      { label: "Total Size", value: fmt(S.total_size_bytes) }
    ];
    cards.innerHTML = items.map((c) => `<div class="card"><div class="card-value">${esc(c.value)}</div><div class="card-label">${esc(c.label)}</div></div>`).join("");
  }
  function matchesSearch(f, q) {
    if (!q) return true;
    const lower = q.toLowerCase();
    return f.path.toLowerCase().includes(lower) || f.root_path.toLowerCase().includes(lower) || f.language.toLowerCase().includes(lower);
  }
  function filterAllSections(q) {
    document.querySelectorAll(".path-section").forEach((section) => {
      const rootPath = section.dataset.rootPath;
      const pathData = R.paths.find((p) => p.root_path === rootPath);
      const tbody = section.querySelector(".file-tbody");
      const count = section.querySelector(".path-file-count");
      const visible = pathData.files.filter((f) => matchesSearch(f, q));
      count.textContent = visible.length + " / " + pathData.files.length + " files";
      tbody.innerHTML = visible.map((f) => renderFileRow(f)).join("");
      attachRowListeners(tbody);
    });
  }
  function renderFileRow(f) {
    return `<tr class="file-row" data-path="${esc(f.path)}" data-root="${esc(f.root_path)}">
        <td>${esc(f.path)}</td>
        <td>${esc(f.language)}</td>
        <td>${f.lines.toLocaleString()}</td>
        <td>${fmt(f.size)}</td>
    </tr>`;
  }
  function attachRowListeners(tbody) {
    tbody.querySelectorAll(".file-row").forEach((row) => {
      row.addEventListener("click", () => {
        const filePath = row.dataset.path;
        const rootPath = row.dataset.root;
        const pathData = R.paths.find((p) => p.root_path === rootPath);
        const file = pathData.files.find((f) => f.path === filePath);
        openCombinedViewer(file);
      });
    });
  }
  function openCombinedViewer(file) {
    const contentKey = file.root_path + ":" + file.path;
    fetchContent(contentKey, (src) => {
      updateContentEntry(file.path, src);
      openViewer({ path: file.path, size: file.size, lines: file.lines, language: file.language });
    });
  }
  function renderPathSection(p, index) {
    const expanded = index === 0;
    const langRows = p.summary.languages.slice(0, 5).map((l) => `<tr><td>${esc(l.name)}</td><td>${l.files}</td><td>${l.lines.toLocaleString()}</td><td>${fmt(l.size_bytes)}</td></tr>`).join("");
    const fileRows = p.files.map((f) => renderFileRow(f)).join("");
    return `
<div class="path-section${expanded ? " expanded" : ""}" data-root-path="${esc(p.root_path)}">
    <div class="path-header" role="button" tabindex="0">
        <span class="path-toggle">${expanded ? "\u25BE" : "\u25B8"}</span>
        <span class="path-name">${esc(p.root_path)}</span>
        <span class="path-stats">${esc(p.summary.source_files)} files \xB7 ${esc(p.summary.total_lines.toLocaleString())} lines \xB7 ${esc(fmt(p.summary.total_size_bytes))}</span>
    </div>
    <div class="path-body" style="${expanded ? "" : "display:none"}">
        <div class="path-summary-row">
            <div class="card"><div class="card-value">${esc(p.summary.source_files)}</div><div class="card-label">Source Files</div></div>
            <div class="card"><div class="card-value">${esc(p.summary.binary_files)}</div><div class="card-label">Binary Files</div></div>
            <div class="card"><div class="card-value">${esc(p.summary.total_lines.toLocaleString())}</div><div class="card-label">Total Lines</div></div>
            <div class="card"><div class="card-value">${esc(fmt(p.summary.total_size_bytes))}</div><div class="card-label">Total Size</div></div>
        </div>
        ${langRows ? `
        <table class="lang-table">
            <thead><tr><th>Language</th><th>Files</th><th>Lines</th><th>Size</th></tr></thead>
            <tbody>${langRows}</tbody>
        </table>` : ""}
        <p class="path-file-count">${p.files.length} files</p>
        <table class="file-table">
            <thead><tr><th>Path</th><th>Language</th><th>Lines</th><th>Size</th></tr></thead>
            <tbody class="file-tbody">${fileRows}</tbody>
        </table>
    </div>
</div>`;
  }
  function attachSectionToggle(section) {
    const header = section.querySelector(".path-header");
    header.addEventListener("click", () => {
      const expanded = section.classList.toggle("expanded");
      const toggle = section.querySelector(".path-toggle");
      const body = section.querySelector(".path-body");
      toggle.textContent = expanded ? "\u25BE" : "\u25B8";
      body.style.display = expanded ? "" : "none";
    });
    header.addEventListener("keydown", (e) => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        header.click();
      }
    });
  }
  function renderPathSections() {
    const container = document.getElementById("path-sections");
    container.innerHTML = R.paths.map((p, i) => renderPathSection(p, i)).join("");
    container.querySelectorAll(".path-section").forEach((section) => {
      attachSectionToggle(section);
      attachRowListeners(section.querySelector(".file-tbody"));
    });
  }
  var searchEl = document.getElementById("search");
  if (searchEl) {
    searchEl.addEventListener("input", () => filterAllSections(searchEl.value.trim()));
  }
  document.getElementById("report-title").textContent = "Code Report: " + M.path_count + " paths";
  document.getElementById("report-meta").textContent = "Generated on " + M.generated_at + " \xB7 ZigZag v" + M.version + (M.failed_paths > 0 ? ` \xB7 \u26A0 ${M.failed_paths} path(s) failed` : "");
  renderGlobalSummary();
  renderPathSections();
})();
