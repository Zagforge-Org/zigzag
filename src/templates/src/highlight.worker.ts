/**
 * Prism syntax highlighting Worker (TypeScript source).
 * Bundled by esbuild into dist/highlight.worker.js.
 *
 * The disableWorkerMessageHandler flag is prepended as a --banner by esbuild
 * so it runs before Prism initialises, preventing Prism from registering its
 * own conflicting message handler.
 */

import Prism from "prismjs";

// Load language grammars (order matters — dependencies first)
import "prismjs/components/prism-markup";
import "prismjs/components/prism-css";
import "prismjs/components/prism-clike";
import "prismjs/components/prism-javascript";
import "prismjs/components/prism-json";
import "prismjs/components/prism-typescript";
import "prismjs/components/prism-jsx";
import "prismjs/components/prism-tsx";
import "prismjs/components/prism-bash";
import "prismjs/components/prism-c";
import "prismjs/components/prism-cpp";
import "prismjs/components/prism-csharp";
import "prismjs/components/prism-clojure";
import "prismjs/components/prism-dart";
import "prismjs/components/prism-elixir";
import "prismjs/components/prism-elm";
import "prismjs/components/prism-erlang";
import "prismjs/components/prism-fsharp";
import "prismjs/components/prism-go";
import "prismjs/components/prism-groovy";
import "prismjs/components/prism-haskell";
import "prismjs/components/prism-java";
import "prismjs/components/prism-julia";
import "prismjs/components/prism-kotlin";
import "prismjs/components/prism-less";
import "prismjs/components/prism-lua";
import "prismjs/components/prism-markdown";
import "prismjs/components/prism-markup-templating";
import "prismjs/components/prism-php";
import "prismjs/components/prism-python";
import "prismjs/components/prism-ruby";
import "prismjs/components/prism-rust";
import "prismjs/components/prism-scala";
import "prismjs/components/prism-scss";
import "prismjs/components/prism-sql";
import "prismjs/components/prism-swift";
import "prismjs/components/prism-toml";
import "prismjs/components/prism-basic";
import "prismjs/components/prism-vbnet";
import "prismjs/components/prism-yaml";

// Custom Zig grammar (not in the prismjs npm package)
Prism.languages["zig"] = {
    comment: [
        { pattern: /\/\/[^\r\n]*/, greedy: true },
        { pattern: /\/\*[\s\S]*?\*\//, greedy: true },
    ],
    string: [
        { pattern: /\\\\[^\r\n]*/, greedy: true },
        { pattern: /"(?:\\.|[^"\\\r\n])*"/, greedy: true },
        { pattern: /'(?:\\.|[^'\\\r\n])'/, alias: "character", greedy: true },
    ],
    builtin: /@\w+/,
    keyword:
        /\b(?:addrspace|align|allowzero|and|anyframe|anytype|asm|async|await|break|callconv|catch|comptime|const|continue|defer|else|enum|errdefer|error|export|extern|fn|for|if|inline|linksection|noalias|noinline|nosuspend|null|opaque|or|orelse|packed|pub|resume|return|struct|suspend|switch|test|threadlocal|try|undefined|union|unreachable|usingnamespace|var|volatile|while)\b/,
    type: /\b(?:anyerror|bool|c_int|c_long|c_longdouble|c_longlong|c_short|c_uint|c_ulong|c_ulonglong|c_ushort|comptime_float|comptime_int|f16|f32|f64|f80|f128|i8|i16|i32|i64|i128|isize|noreturn|type|u1|u8|u16|u32|u64|u128|usize|void)\b/,
    number: /\b0x[\da-fA-F][_\da-fA-F]*(?:\.[\da-fA-F][_\da-fA-F]*)?(?:[pP][+-]?\d+)?\b|\b0o[0-7][_0-7]*\b|\b0b[01][_01]*\b|\b\d+(?:_\d+)*(?:\.\d+(?:_\d+)*)?(?:[eE][+-]?\d+)?\b/,
    boolean: /\b(?:false|true)\b/,
    operator: /\.{2,3}|[*!%&+\-/<=>|~^?]/,
    punctuation: /[{}[\];(),.:]/,
};
(Prism.languages["zig"] as { type: { alias: string } }).type.alias = "keyword";

// ── Worker message handler ────────────────────────────────────────────────────

function escHtml(s: string): string {
    return String(s)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;");
}

self.onmessage = function (e: MessageEvent<{ id: number; code: string; language: string }>) {
    const { id, code, language } = e.data;
    let html: string;
    try {
        const grammar = Prism.languages[language];
        html = grammar ? Prism.highlight(code, grammar, language) : escHtml(code);
    } catch {
        html = escHtml(code);
    }
    self.postMessage({ id, html });
};
