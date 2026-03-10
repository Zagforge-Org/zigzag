export const VIRT_LINE_THRESHOLD = 500;
export const VIRT_BYTE_THRESHOLD = 200 * 1024; // 200 KB
export const VIEWER_LINE_HEIGHT = 20; // px — must match CSS .vline height
export const VIEWER_OVERSCAN = 15;
export const HL_CHUNK_SIZE = 200;
// Lines longer than this are truncated at display time (badge shows remaining chars).
// The full line is preserved in virtLines for correct line numbers and copy semantics.
export const DISPLAY_TRUNCATE_AT = 2_000;
// A single line longer than this triggers the minified-file heuristic.
export const MINIFIED_LINE_THRESHOLD = 10_000;
// If the file has ≤5 newlines and is larger than this, it's treated as minified.
export const MINIFIED_FILE_THRESHOLD = 50_000;
// How many characters of a minified file to show in the preview pane.
export const MINIFIED_DISPLAY_CHARS = 10_000;

export const PRISM_MAP: Record<string, string> = {
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
