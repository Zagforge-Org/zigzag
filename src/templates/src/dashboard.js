/**
 * ZigZag Dashboard — application logic.
 * ES5 compatible. No external dependencies at runtime.
 * Prism runs in a Blob Worker (loaded from #prism-src element).
 */
(function () {
    "use strict";

    var R = window.REPORT,
        M = R.meta,
        S = R.summary,
        F = R.files,
        B = R.binaries,
        L = S.languages;

    // ── Helpers ──────────────────────────────────────────
    function fmt(n) {
        if (n >= 1073741824) return (n / 1073741824).toFixed(1) + " GB";
        if (n >= 1048576) return (n / 1048576).toFixed(1) + " MB";
        if (n >= 1024) return (n / 1024).toFixed(1) + " KB";
        return n + " B";
    }
    function fmtNum(n) {
        return n.toLocaleString();
    }
    function el(tag, cls, html) {
        var e = document.createElement(tag);
        if (cls) e.className = cls;
        if (html) e.innerHTML = html;
        return e;
    }
    function esc(s) {
        return String(s)
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;");
    }

    // ── Virtual viewer thresholds & constants ─────────────
    var VIRT_LINE_THRESHOLD = 500;
    var VIRT_BYTE_THRESHOLD = 200 * 1024; // 200 KB
    var VIEWER_LINE_HEIGHT = 20; // px — must match CSS .vline height
    var VIEWER_OVERSCAN = 15;
    var HL_CHUNK_SIZE = 200;

    // ── Prism language map ────────────────────────────────
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
        sql: "sql",
    };

    // ── Highlight worker (lazy, off-thread Prism) ─────────
    var hlWorker = null;
    var hlReqId = 0;
    var hlReqMap = {}; // id → callback

    function getHighlightWorker() {
        if (hlWorker) return hlWorker;
        var src = document.getElementById("prism-src");
        if (!src) return null;
        try {
            var blob = new Blob([src.textContent], { type: "text/javascript" });
            hlWorker = new Worker(URL.createObjectURL(blob));
            hlWorker.onmessage = function (e) {
                var cb = hlReqMap[e.data.id];
                if (!cb) return;
                delete hlReqMap[e.data.id];
                cb(e.data.html);
            };
            hlWorker.onerror = function () {
                hlWorker = null;
            };
        } catch (x) {
            hlWorker = null;
        }
        return hlWorker;
    }

    function highlightAsync(code, language, cb) {
        var w = getHighlightWorker();
        if (!w) {
            cb(null);
            return;
        }
        var id = hlReqId++;
        hlReqMap[id] = cb;
        w.postMessage({ id: id, code: code, language: language });
    }

    // ── Content worker (off-thread JSON.parse for file content) ──
    var CONTENT_WORKER_SRC = [
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

    var contentCache = {};
    var contentReqId = 0;
    var contentReqMap = {};
    var contentWorker = null;

    function createContentWorker() {
        var blob = new Blob([CONTENT_WORKER_SRC], { type: "text/javascript" });
        var w = new Worker(URL.createObjectURL(blob));
        w.onmessage = function (e) {
            var req = contentReqMap[e.data.id];
            if (!req) return;
            delete contentReqMap[e.data.id];
            contentCache[req.key] = e.data.c;
            req.cb(e.data.c);
        };
        return w;
    }

    function fetchContent(path, cb) {
        if (Object.prototype.hasOwnProperty.call(contentCache, path)) {
            cb(contentCache[path]);
            return;
        }
        if (!contentWorker) {
            cb("");
            return;
        }
        var id = contentReqId++;
        contentReqMap[id] = { key: path, cb: cb };
        contentWorker.postMessage({ cmd: "get", id: id, k: path });
    }

    function initContentWorker(jsonText) {
        if (contentWorker) {
            try {
                contentWorker.terminate();
            } catch (x) {}
        }
        contentCache = {};
        contentReqMap = {};
        try {
            contentWorker = createContentWorker();
            contentWorker.postMessage({ cmd: "init", json: jsonText });
        } catch (x) {
            contentWorker = null;
            try {
                contentCache = JSON.parse(jsonText);
            } catch (y) {
                contentCache = {};
            }
        }
    }

    // Kick off background parsing immediately.
    initContentWorker(document.getElementById("fc").textContent);

    // ── Header & summary cards ────────────────────────────
    function renderHeader() {
        document.getElementById("report-title").textContent =
            "Code Report: " + M.root_path;
        document.getElementById("report-meta").textContent =
            "Generated on " + M.generated_at + " · ZigZag v" + M.version;
    }

    function renderCards() {
        var defs = [
            { val: fmtNum(S.source_files), lbl: "Source Files" },
            { val: fmtNum(S.total_lines), lbl: "Total Lines" },
            { val: fmtNum(S.binary_files), lbl: "Binary Files" },
            { val: fmt(S.total_size_bytes), lbl: "Total Size" },
        ];
        var cardEl = document.getElementById("cards");
        cardEl.innerHTML = "";
        defs.forEach(function (c) {
            var d = el("div", "card");
            d.innerHTML =
                '<div class="val">' +
                c.val +
                '</div><div class="lbl">' +
                c.lbl +
                "</div>";
            cardEl.appendChild(d);
        });
    }

    function renderLangChart() {
        var langEl = document.getElementById("chart-lang");
        langEl.innerHTML = "";
        if (L && L.length) {
            var sorted = [].concat(L).sort(function (a, b) {
                return b.files - a.files;
            });
            var max = sorted[0].files || 1;
            sorted.forEach(function (lg) {
                var row = el("div", "bar-row");
                row.innerHTML =
                    '<span class="name">' +
                    esc(lg.name) +
                    "</span>" +
                    '<span class="bar-track"><span class="bar-fill" style="width:' +
                    Math.round((lg.files / max) * 100) +
                    '%"></span></span>' +
                    '<span class="bar-count">' +
                    lg.files +
                    " file" +
                    (lg.files !== 1 ? "s" : "") +
                    "</span>";
                langEl.appendChild(row);
            });
        } else {
            langEl.textContent = "No source files.";
        }
    }

    function renderSizeChart() {
        var buckets = [
            { lbl: "<1 KB", max: 1024 },
            { lbl: "1\u201310 KB", max: 10240 },
            { lbl: "10\u2013100 KB", max: 102400 },
            { lbl: "100 KB\u20131 MB", max: 1048576 },
            { lbl: ">1 MB", max: Infinity },
        ];
        buckets.forEach(function (b) {
            b.count = 0;
        });
        (F || []).concat(B || []).forEach(function (f) {
            for (var i = 0; i < buckets.length; i++) {
                if (f.size < buckets[i].max) {
                    buckets[i].count++;
                    break;
                }
            }
        });
        var sizeEl = document.getElementById("chart-size");
        sizeEl.innerHTML = "";
        var histMax = buckets.reduce(function (m, b) {
            return Math.max(m, b.count);
        }, 1);
        var hist = el("div", "hist");
        buckets.forEach(function (b) {
            var col = el("div", "hist-col");
            var h = Math.max(2, Math.round((b.count / histMax) * 90));
            col.innerHTML =
                '<div class="hist-bar" style="height:' +
                h +
                'px" title="' +
                b.count +
                ' files"></div>' +
                '<div class="hist-lbl">' +
                b.lbl +
                "<br><strong>" +
                b.count +
                "</strong></div>";
            hist.appendChild(col);
        });
        sizeEl.appendChild(hist);
    }

    // ── Source viewer ─────────────────────────────────────
    var viewer = document.getElementById("viewer");
    var vpath = document.getElementById("viewer-path");
    var viewerToken = 0;
    var currentFile = null;

    // Virtual viewer state (null/empty when viewer is closed)
    var virtLines = null;
    var virtLangKey = null;
    var virtBodyEl = null;
    var virtWindowEl = null;
    var virtSpacerTopEl = null;
    var virtSpacerBotEl = null;
    var virtGutterW = "3ch";
    var virtRafPending = false;
    var hlChunkCache = {};
    var hlChunkPending = {};

    function openViewer(f) {
        currentFile = f;
        viewerToken++;
        var myToken = viewerToken;

        // Reset virtual state from any previous open
        virtLines = null;
        virtLangKey = null;
        virtRafPending = false;
        hlChunkCache = {};
        hlChunkPending = {};
        if (virtBodyEl) {
            virtBodyEl.removeEventListener("scroll", scheduleVirtualViewerRender);
            virtBodyEl = null;
        }
        virtWindowEl = null;
        virtSpacerTopEl = null;
        virtSpacerBotEl = null;

        vpath.textContent = f.path;
        viewer.classList.add("open");

        var body = document.getElementById("viewer-body");
        body.innerHTML =
            '<div style="padding:0.75rem 1rem;color:#adb5bd;font-size:0.8rem">Loading\u2026</div>';
        body.scrollTop = 0;

        fetchContent(f.path, function (raw) {
            if (viewerToken !== myToken) return;
            var content = (raw || "(binary or empty)").replace(/\r\n/g, "\n").replace(/\r/g, "\n");
            var lines = content.split("\n");
            var langKey = PRISM_MAP[f.language || ""] || null;

            if (
                lines.length > VIRT_LINE_THRESHOLD ||
                content.length > VIRT_BYTE_THRESHOLD
            ) {
                openVirtualViewer(lines, langKey, myToken);
            } else {
                openSimpleViewer(content, lines, langKey, myToken);
            }
        });
    }

    function openSimpleViewer(content, lines, langKey, myToken) {
        var body = document.getElementById("viewer-body");
        // Add 2rem for the td.ln padding so the digit content area is actually N ch
        var numWidth = "calc(" + String(lines.length).length + "ch + 2rem)";

        var rows = [];
        for (var i = 0; i < lines.length; i++) {
            rows.push(
                '<tr><td class="ln" style="min-width:' +
                    numWidth +
                    '">' +
                    (i + 1) +
                    '</td><td class="lc" data-line="' +
                    i +
                    '">' +
                    esc(lines[i]) +
                    "</td></tr>"
            );
        }
        body.innerHTML =
            '<table class="ln-table"><tbody>' +
            rows.join("") +
            "</tbody></table>";
        body.scrollTop = 0;

        if (!langKey) return;

        highlightAsync(content, langKey, function (highlighted) {
            if (viewerToken !== myToken) return;
            if (!highlighted) return;
            var hlLines = highlighted.split("\n");
            var cells = body.querySelectorAll("td.lc[data-line]");
            for (var j = 0; j < cells.length; j++) {
                var idx = parseInt(cells[j].dataset.line, 10);
                if (hlLines[idx] !== undefined) cells[j].innerHTML = hlLines[idx];
            }
        });
    }

    function openVirtualViewer(lines, langKey, myToken) {
        virtLines = lines;
        virtLangKey = langKey;

        // Width of the line-number gutter. With box-sizing: border-box and
        // padding: 0 1rem on .ln, we must add the 2rem padding to the digit
        // width so the content area is actually N ch wide.
        var digits = String(lines.length).length;
        virtGutterW = "calc(" + digits + "ch + 2rem)";

        // Pre-scan for the longest line so we can set a stable minWidth on the
        // vwindow upfront. This prevents the horizontal scrollbar from
        // appearing/disappearing during scroll, which would oscillate
        // clientHeight and destabilise the vertical scroll calculation.
        var maxLen = 0;
        for (var mi = 0; mi < lines.length; mi++) {
            if (lines[mi].length > maxLen) maxLen = lines[mi].length;
        }

        var body = document.getElementById("viewer-body");
        body.innerHTML = "";
        body.scrollTop = 0;
        virtBodyEl = body;

        var spacerTop = document.createElement("div");
        var win = document.createElement("div");
        win.className = "vwindow";
        // gutter (digits ch + 2rem padding) + code (maxLen ch) + code right padding (1rem)
        win.style.minWidth = "calc(" + (digits + maxLen) + "ch + 3rem)";
        var spacerBot = document.createElement("div");

        body.appendChild(spacerTop);
        body.appendChild(win);
        body.appendChild(spacerBot);

        virtSpacerTopEl = spacerTop;
        virtWindowEl = win;
        virtSpacerBotEl = spacerBot;

        body.addEventListener("scroll", scheduleVirtualViewerRender);
        renderVirtualWindow();
    }

    function scheduleVirtualViewerRender() {
        if (virtRafPending || !virtLines) return;
        virtRafPending = true;
        requestAnimationFrame(function () {
            virtRafPending = false;
            if (virtLines) renderVirtualWindow();
        });
    }

    function renderVirtualWindow() {
        if (!virtLines || !virtBodyEl || !virtWindowEl) return;
        var total = virtLines.length;
        var scrollTop = virtBodyEl.scrollTop;
        var viewH = virtBodyEl.clientHeight;

        var start = Math.max(
            0,
            Math.floor(scrollTop / VIEWER_LINE_HEIGHT) - VIEWER_OVERSCAN
        );
        var end = Math.min(
            total,
            Math.ceil((scrollTop + viewH) / VIEWER_LINE_HEIGHT) + VIEWER_OVERSCAN
        );

        // Pin vwindow height before clearing to prevent scrollHeight collapsing,
        // which would cause the browser to clamp scrollTop and jump the view.
        virtWindowEl.style.height = (end - start) * VIEWER_LINE_HEIGHT + "px";
        virtSpacerTopEl.style.height = start * VIEWER_LINE_HEIGHT + "px";
        virtSpacerBotEl.style.height =
            (total - end) * VIEWER_LINE_HEIGHT + "px";

        var frag = document.createDocumentFragment();
        for (var i = start; i < end; i++) {
            var row = document.createElement("div");
            row.className = "vline";

            var ln = document.createElement("span");
            ln.className = "ln";
            ln.style.width = virtGutterW;
            ln.textContent = i + 1;

            var lc = document.createElement("span");
            lc.className = "lc";
            lc.dataset.line = i;

            var chunkIdx = Math.floor(i / HL_CHUNK_SIZE);
            var lineInChunk = i - chunkIdx * HL_CHUNK_SIZE;
            if (
                hlChunkCache[chunkIdx] &&
                hlChunkCache[chunkIdx][lineInChunk] !== undefined
            ) {
                lc.innerHTML = hlChunkCache[chunkIdx][lineInChunk];
            } else {
                lc.textContent = virtLines[i];
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
        var firstChunk = Math.floor(start / HL_CHUNK_SIZE);
        var lastChunk = Math.floor(Math.max(start, end - 1) / HL_CHUNK_SIZE);

        for (var c = firstChunk; c <= lastChunk; c++) {
            if (hlChunkCache[c] || hlChunkPending[c]) continue;
            hlChunkPending[c] = true;
            (function (chunkIdx, myToken) {
                var chunkStart = chunkIdx * HL_CHUNK_SIZE;
                var chunkEnd = Math.min(virtLines.length, chunkStart + HL_CHUNK_SIZE);
                var chunkText = virtLines.slice(chunkStart, chunkEnd).join("\n");

                highlightAsync(chunkText, virtLangKey, function (html) {
                    if (viewerToken !== myToken || !virtLines) return;
                    delete hlChunkPending[chunkIdx];
                    if (!html) return;

                    var hlLines = html.split("\n");
                    hlChunkCache[chunkIdx] = hlLines;

                    if (!virtWindowEl) return;
                    var cells = virtWindowEl.querySelectorAll(".lc[data-line]");
                    for (var j = 0; j < cells.length; j++) {
                        var lineIdx = parseInt(cells[j].dataset.line, 10);
                        if (Math.floor(lineIdx / HL_CHUNK_SIZE) !== chunkIdx) continue;
                        var lineInChunk = lineIdx - chunkStart;
                        cells[j].innerHTML =
                            hlLines[lineInChunk] !== undefined
                                ? hlLines[lineInChunk]
                                : esc(virtLines[lineIdx]);
                    }
                });
            })(c, token);
        }
    }

    function closeViewer() {
        viewer.classList.remove("open");
        currentFile = null;
        viewerToken++;

        virtLines = null;
        virtLangKey = null;
        virtRafPending = false;
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

    document
        .getElementById("viewer-close")
        .addEventListener("click", closeViewer);
    document.addEventListener("keydown", function (e) {
        if (e.key === "Escape") closeViewer();
    });

    // ── Virtual file table ────────────────────────────────
    var ROW_H = 40;
    var OVERSCAN = 10;

    var cols = ["path", "lines", "size", "language"];
    var sortCol = "path";
    var sortAsc = true;
    var search = document.getElementById("search");
    var tableWrap = document.getElementById("files-table");

    var tableFiles = [];
    var tableViewport = null;
    var tableTopSpacer = null;
    var tableBottomSpacer = null;
    var tableTbody = null;
    var rafPending = false;

    function buildTableDOM() {
        tableViewport = el("div", "table-viewport");

        var table = el("table");

        // Sticky header
        var hdr = el("thead");
        var hdrRow = el("tr");
        cols.forEach(function (c) {
            var th = el("th");
            var arrow =
                c === sortCol
                    ? sortAsc
                        ? "&#x2191;"
                        : "&#x2193;"
                    : "&#x2195;";
            if (c === sortCol) th.className = "sorted";
            th.dataset.col = c;
            th.innerHTML =
                c.charAt(0).toUpperCase() +
                c.slice(1) +
                '<span class="sort-icon">' +
                arrow +
                "</span>";
            hdrRow.appendChild(th);
        });
        hdr.appendChild(hdrRow);
        table.appendChild(hdr);

        // Virtual body with spacer rows
        tableTbody = el("tbody");
        tableTopSpacer = el("tr");
        tableTopSpacer.style.height = "0";
        tableBottomSpacer = el("tr");
        tableBottomSpacer.style.height = "0";
        var topTd = document.createElement("td");
        topTd.colSpan = 4;
        topTd.style.cssText = "padding:0;border:none;";
        var botTd = document.createElement("td");
        botTd.colSpan = 4;
        botTd.style.cssText = "padding:0;border:none;";
        tableTopSpacer.appendChild(topTd);
        tableBottomSpacer.appendChild(botTd);
        tableTbody.appendChild(tableTopSpacer);
        tableTbody.appendChild(tableBottomSpacer);
        table.appendChild(tableTbody);

        tableViewport.appendChild(table);

        // Header sort — delegated
        hdr.addEventListener("click", function (e) {
            var th = e.target.closest ? e.target.closest("th[data-col]") : null;
            if (!th) return;
            var c = th.dataset.col;
            if (sortCol === c) sortAsc = !sortAsc;
            else {
                sortCol = c;
                sortAsc = true;
            }
            renderTable();
        });

        // Row clicks — delegated
        tableViewport.addEventListener("click", function (e) {
            var span = e.target;
            if (span.className === "file-link") {
                openViewer(tableFiles[parseInt(span.dataset.idx, 10)]);
            }
        });

        // Hover prefetch — delegated
        tableViewport.addEventListener("mouseover", function (e) {
            var span = e.target;
            if (span.className !== "file-link") return;
            var idx = parseInt(span.dataset.idx, 10);
            if (isNaN(idx)) return;
            var f = tableFiles[idx];
            if (
                f &&
                !Object.prototype.hasOwnProperty.call(contentCache, f.path)
            ) {
                fetchContent(f.path, function () {}); // fire-and-forget prefetch
            }
        });

        // Scroll handler — throttled via RAF
        tableViewport.addEventListener("scroll", scheduleVirtualRender);
    }

    function scheduleVirtualRender() {
        if (rafPending) return;
        rafPending = true;
        requestAnimationFrame(function () {
            rafPending = false;
            renderVisibleRows();
        });
    }

    function renderVisibleRows() {
        var total = tableFiles.length;
        var scrollTop = tableViewport.scrollTop;
        var viewH = tableViewport.clientHeight;

        var start = Math.max(0, Math.floor(scrollTop / ROW_H) - OVERSCAN);
        var end = Math.min(
            total,
            Math.ceil((scrollTop + viewH) / ROW_H) + OVERSCAN,
        );

        tableTopSpacer.style.height = start * ROW_H + "px";
        tableBottomSpacer.style.height = (total - end) * ROW_H + "px";

        // Remove existing data rows (between spacers)
        while (tableTopSpacer.nextSibling !== tableBottomSpacer) {
            tableTbody.removeChild(tableTopSpacer.nextSibling);
        }

        // Append visible rows
        var frag = document.createDocumentFragment();
        for (var i = start; i < end; i++) {
            var f = tableFiles[i];
            var tr = document.createElement("tr");
            tr.style.height = ROW_H + "px";
            tr.innerHTML =
                '<td><span class="file-link" data-idx="' +
                i +
                '">' +
                esc(f.path) +
                "</span></td>" +
                "<td><span>" +
                fmtNum(f.lines) +
                "</span></td>" +
                "<td><span>" +
                fmt(f.size) +
                "</span></td>" +
                '<td><span class="tag">' +
                esc(f.language || "\u2014") +
                "</span></td>";
            frag.appendChild(tr);
        }
        tableTbody.insertBefore(frag, tableBottomSpacer);
    }

    function updateHeaderSortIndicators() {
        if (!tableViewport) return;
        tableViewport.querySelectorAll("th[data-col]").forEach(function (th) {
            var c = th.dataset.col;
            th.className = c === sortCol ? "sorted" : "";
            var arrow =
                c === sortCol
                    ? sortAsc
                        ? "&#x2191;"
                        : "&#x2193;"
                    : "&#x2195;";
            th.innerHTML =
                c.charAt(0).toUpperCase() +
                c.slice(1) +
                '<span class="sort-icon">' +
                arrow +
                "</span>";
        });
    }

    function renderTable() {
        var query = (search.value || "").toLowerCase();
        tableFiles = (F || []).filter(function (f) {
            return !query || f.path.toLowerCase().indexOf(query) >= 0;
        });
        tableFiles.sort(function (a, b) {
            var av = a[sortCol],
                bv = b[sortCol];
            if (typeof av === "number") return sortAsc ? av - bv : bv - av;
            return sortAsc
                ? String(av).localeCompare(String(bv))
                : String(bv).localeCompare(String(av));
        });
        updateHeaderSortIndicators();
        tableViewport.scrollTop = 0;
        renderVisibleRows();
    }

    var searchTimer = 0;
    search.addEventListener("input", function () {
        clearTimeout(searchTimer);
        searchTimer = setTimeout(renderTable, 150);
    });

    // ── Initial render ────────────────────────────────────
    renderHeader();
    renderCards();
    renderLangChart();
    renderSizeChart();
    buildTableDOM();
    tableWrap.appendChild(tableViewport);
    renderTable();

    // ── Watch mode: soft update (no full page reload) ─────
    if (M.watch_mode) {
        function extractReport(html) {
            var m = /id="rpt"[^>]*>([\s\S]*?)<\/script>/i.exec(html);
            if (!m) return null;
            try {
                return JSON.parse(m[1]);
            } catch (e) {
                return null;
            }
        }

        function softUpdate(newR, newContentText) {
            window.REPORT = newR;
            R = newR;
            M = newR.meta;
            S = newR.summary;
            F = newR.files;
            B = newR.binaries;
            L = S.languages;
            if (newContentText) {
                document.getElementById("fc").textContent = newContentText;
                initContentWorker(newContentText);
            }
            renderHeader();
            renderCards();
            renderLangChart();
            renderSizeChart();
            renderTable();
            if (currentFile !== null) {
                var updated = null;
                for (var i = 0; i < F.length; i++) {
                    if (F[i].path === currentFile.path) {
                        updated = F[i];
                        break;
                    }
                }
                if (updated) openViewer(updated);
                else closeViewer();
            }
        }

        function extractGeneratedAt(html) {
            var m = /"generated_at"\s*:\s*"([^"]+)"/.exec(html);
            return m ? m[1] : null;
        }

        function extractContent(html) {
            var m = /id="fc"[^>]*>([\s\S]*?)<\/script>/i.exec(html);
            return m ? m[1] : null;
        }

        function poll() {
            fetch(location.href, { cache: "no-store" })
                .then(function (r) {
                    return r.text();
                })
                .then(function (html) {
                    var newAt = extractGeneratedAt(html);
                    if (newAt && newAt !== window.REPORT.meta.generated_at) {
                        var newR = extractReport(html);
                        var newContent = extractContent(html);
                        if (newR) softUpdate(newR, newContent);
                    }
                })
                .catch(function () {})
                .then(function () {
                    setTimeout(poll, 2000);
                });
        }
        setTimeout(poll, 2000);
    }
})();
