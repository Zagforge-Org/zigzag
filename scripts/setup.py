"""
Cross-platform setup script for zigzag.

Usage:
    python scripts/setup.py          # init + build
    python scripts/setup.py init     # init submodules (sparse checkout)
    python scripts/setup.py build    # build release binary
    python scripts/setup.py test     # compile C objects and run zig tests
    python scripts/setup.py all      # init + build + test
"""

import io
import shutil
import subprocess
import sys
import tarfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / ".zig-cache"

SWIFT_PARSER_URL = "https://github.com/alex-pinkus/tree-sitter-swift/releases/download/0.7.1/tree-sitter-swift.tar.gz"

TS_SRC = ROOT / "ast/vendor/tree-sitter/lib/src"
TS_INCLUDE_FLAGS = [
    "-Iast/vendor/tree-sitter/lib/include",
    "-Iast/vendor/tree-sitter/lib/src",
    "-Iast/src",
    "-Iast/grammars/tree-sitter-python/src",
    "-Iast/grammars/tree-sitter-javascript/src",
    "-Iast/grammars/tree-sitter-zig/src",
    "-Iast/grammars/tree-sitter-typescript/typescript/src",
    "-Iast/grammars/tree-sitter-typescript/tsx/src",
    "-Iast/grammars/tree-sitter-rust/src",
    "-Iast/grammars/tree-sitter-go/src",
    "-Iast/grammars/tree-sitter-c/src",
    "-Iast/grammars/tree-sitter-cpp/src",
    "-Iast/grammars/tree-sitter-java/src",
    "-Iast/grammars/tree-sitter-c-sharp/src",
    "-Iast/grammars/tree-sitter-ruby/src",
    "-Iast/grammars/tree-sitter-elixir/src",
    "-Iast/grammars/tree-sitter-kotlin/src",
    "-Iast/grammars/tree-sitter-swift/src",
    "-Iast/grammars/tree-sitter-lua/src",
]

TS_C_SOURCES = [
    (TS_SRC / "alloc.c", CACHE / "ts_alloc.o"),
    (TS_SRC / "get_changed_ranges.c", CACHE / "ts_get_changed_ranges.o"),
    (TS_SRC / "language.c", CACHE / "ts_language.o"),
    (TS_SRC / "lexer.c", CACHE / "ts_lexer.o"),
    (TS_SRC / "node.c", CACHE / "ts_node.o"),
    (TS_SRC / "parser.c", CACHE / "ts_parser.o"),
    (TS_SRC / "query.c", CACHE / "ts_query.o"),
    (TS_SRC / "stack.c", CACHE / "ts_stack.o"),
    (TS_SRC / "subtree.c", CACHE / "ts_subtree.o"),
    (TS_SRC / "tree_cursor.c", CACHE / "ts_tree_cursor.o"),
    (TS_SRC / "tree.c", CACHE / "ts_tree.o"),
    (TS_SRC / "wasm_store.c", CACHE / "ts_wasm_store.o"),
    (ROOT / "ast/grammars/tree-sitter-python/src/parser.c", CACHE / "ts_py_parser.o"),
    (ROOT / "ast/grammars/tree-sitter-python/src/scanner.c", CACHE / "ts_py_scanner.o"),
    (ROOT / "ast/grammars/tree-sitter-javascript/src/parser.c", CACHE / "ts_js_parser.o"),
    (ROOT / "ast/grammars/tree-sitter-javascript/src/scanner.c", CACHE / "ts_js_scanner.o"),
    (ROOT / "ast/grammars/tree-sitter-zig/src/parser.c", CACHE / "ts_zig_parser.o"),
    (ROOT / "ast/grammars/tree-sitter-typescript/typescript/src/parser.c", CACHE / "ts_ts_parser.o"),
    (ROOT / "ast/grammars/tree-sitter-typescript/typescript/src/scanner.c", CACHE / "ts_ts_scanner.o"),
    (ROOT / "ast/grammars/tree-sitter-typescript/tsx/src/parser.c", CACHE / "ts_tsx_parser.o"),
    (ROOT / "ast/grammars/tree-sitter-typescript/tsx/src/scanner.c", CACHE / "ts_tsx_scanner.o"),
    (ROOT / "ast/grammars/tree-sitter-rust/src/parser.c",  CACHE / "ts_rust_parser.o"),
    (ROOT / "ast/grammars/tree-sitter-rust/src/scanner.c", CACHE / "ts_rust_scanner.o"),
    (ROOT / "ast/grammars/tree-sitter-go/src/parser.c", CACHE / "ts_go_parser.o"),
    (ROOT / "ast/grammars/tree-sitter-c/src/parser.c",    CACHE / "ts_c_parser.o"),
    (ROOT / "ast/grammars/tree-sitter-cpp/src/parser.c",  CACHE / "ts_cpp_parser.o"),
    (ROOT / "ast/grammars/tree-sitter-cpp/src/scanner.c", CACHE / "ts_cpp_scanner.o"),
    (ROOT / "ast/grammars/tree-sitter-java/src/parser.c", CACHE / "ts_java_parser.o"),
    (ROOT / "ast/grammars/tree-sitter-c-sharp/src/parser.c", CACHE / "ts_cs_parser.o"),
    (ROOT / "ast/grammars/tree-sitter-c-sharp/src/scanner.c", CACHE / "ts_cs_scanner.o"),
    (ROOT / "ast/grammars/tree-sitter-ruby/src/parser.c", CACHE / "ts_ruby_parser.o"),
    (ROOT / "ast/grammars/tree-sitter-ruby/src/scanner.c", CACHE / "ts_ruby_scanner.o"),
    (ROOT / "ast/grammars/tree-sitter-elixir/src/parser.c", CACHE / "ts_elixir_parser.o"),
    (ROOT / "ast/grammars/tree-sitter-elixir/src/scanner.c", CACHE / "ts_elixir_scanner.o"),
    (ROOT / "ast/grammars/tree-sitter-kotlin/src/parser.c", CACHE / "ts_kotlin_parser.o"),
    (ROOT / "ast/grammars/tree-sitter-kotlin/src/scanner.c", CACHE / "ts_kotlin_scanner.o"),
    (ROOT / "ast/grammars/tree-sitter-swift/src/parser.c", CACHE / "ts_swift_parser.o"),
    (ROOT / "ast/grammars/tree-sitter-swift/src/scanner.c", CACHE / "ts_swift_scanner.o"),
    (ROOT / "ast/grammars/tree-sitter-lua/src/parser.c", CACHE / "ts_lua_parser.o"),
    (ROOT / "ast/grammars/tree-sitter-lua/src/scanner.c", CACHE / "ts_lua_scanner.o"),
    (ROOT / "ast/src/chunker.c", CACHE / "ts_chunker.o"),
]


def run(cmd: list, **kwargs):
    print(f"  $ {' '.join(str(c) for c in cmd)}")
    subprocess.run(cmd, check=True, **kwargs)


def check_deps():
    missing = [tool for tool in ("git", "zig") if not shutil.which(tool)]
    if missing:
        print(f"Missing required tools: {', '.join(missing)}")
        print("Please install them and try again.")
        sys.exit(1)

    git_ver = subprocess.run(
        ["git", "--version"], capture_output=True, text=True, check=True
    )
    zig_ver = subprocess.run(
        ["zig", "version"], capture_output=True, text=True, check=True
    )
    print(f"Using {git_ver.stdout.strip()}")
    print(f"Using zig {zig_ver.stdout.strip()}")


def init():
    print("\n==> Initializing submodules...")
    run(["git", "submodule", "update", "--init", "--depth", "1"], cwd=ROOT)
    run(
        ["git", "-C", "ast/vendor/tree-sitter", "sparse-checkout", "init", "--cone"],
        cwd=ROOT,
    )
    run(
        ["git", "-C", "ast/vendor/tree-sitter", "sparse-checkout", "set", "lib"],
        cwd=ROOT,
    )
    run(
        [
            "git",
            "-C",
            "ast/grammars/tree-sitter-python",
            "sparse-checkout",
            "init",
            "--cone",
        ],
        cwd=ROOT,
    )
    run(
        [
            "git",
            "-C",
            "ast/grammars/tree-sitter-python",
            "sparse-checkout",
            "set",
            "src",
        ],
        cwd=ROOT,
    )
    run(
        [
            "git",
            "-C",
            "ast/grammars/tree-sitter-javascript",
            "sparse-checkout",
            "init",
            "--cone",
        ],
        cwd=ROOT,
    )
    run(
        [
            "git",
            "-C",
            "ast/grammars/tree-sitter-javascript",
            "sparse-checkout",
            "set",
            "src",
        ],
        cwd=ROOT,
    )
    run(
        [
            "git",
            "-C",
            "ast/grammars/tree-sitter-zig",
            "sparse-checkout",
            "init",
            "--cone",
        ],
        cwd=ROOT,
    )
    run(
        [
            "git",
            "-C",
            "ast/grammars/tree-sitter-zig",
            "sparse-checkout",
            "set",
            "src",
        ],
        cwd=ROOT,
    )
    run(
        [
            "git",
            "-C",
            "ast/grammars/tree-sitter-typescript",
            "sparse-checkout",
            "init",
            "--cone",
        ],
        cwd=ROOT,
    )
    run(
        [
            "git",
            "-C",
            "ast/grammars/tree-sitter-typescript",
            "sparse-checkout",
            "set",
            "typescript/src",
            "tsx/src",
            "common",
        ],
        cwd=ROOT,
    )
    run(
        ["git", "-C", "ast/grammars/tree-sitter-rust", "sparse-checkout", "init", "--cone"],
        cwd=ROOT,
    )
    run(
        ["git", "-C", "ast/grammars/tree-sitter-rust", "sparse-checkout", "set", "src"],
        cwd=ROOT,
    )
    run(
        ["git", "-C", "ast/grammars/tree-sitter-go", "sparse-checkout", "init", "--cone"],
        cwd=ROOT,
    )
    run(
        ["git", "-C", "ast/grammars/tree-sitter-go", "sparse-checkout", "set", "src"],
        cwd=ROOT,
    )
    run(
        ["git", "-C", "ast/grammars/tree-sitter-c", "sparse-checkout", "init", "--cone"],
        cwd=ROOT,
    )
    run(
        ["git", "-C", "ast/grammars/tree-sitter-c", "sparse-checkout", "set", "src"],
        cwd=ROOT,
    )
    run(
        ["git", "-C", "ast/grammars/tree-sitter-cpp", "sparse-checkout", "init", "--cone"],
        cwd=ROOT,
    )
    run(
        ["git", "-C", "ast/grammars/tree-sitter-cpp", "sparse-checkout", "set", "src"],
        cwd=ROOT,
    )
    run(
        ["git", "-C", "ast/grammars/tree-sitter-java", "sparse-checkout", "init", "--cone"],
        cwd=ROOT,
    )
    run(
        ["git", "-C", "ast/grammars/tree-sitter-java", "sparse-checkout", "set", "src"],
        cwd=ROOT,
    )
    run(
        ["git", "-C", "ast/grammars/tree-sitter-c-sharp", "sparse-checkout", "init", "--cone"],
        cwd=ROOT,
    )
    run(
        ["git", "-C", "ast/grammars/tree-sitter-c-sharp", "sparse-checkout", "set", "src"],
        cwd=ROOT,
    )
    run(
        ["git", "-C", "ast/grammars/tree-sitter-ruby", "sparse-checkout", "init", "--cone"],
        cwd=ROOT,
    )
    run(
        ["git", "-C", "ast/grammars/tree-sitter-ruby", "sparse-checkout", "set", "src"],
        cwd=ROOT,
    )
    run(
        ["git", "-C", "ast/grammars/tree-sitter-elixir", "sparse-checkout", "init", "--cone"],
        cwd=ROOT,
    )
    run(
        ["git", "-C", "ast/grammars/tree-sitter-elixir", "sparse-checkout", "set", "src"],
        cwd=ROOT,
    )
    run(
        ["git", "-C", "ast/grammars/tree-sitter-kotlin", "sparse-checkout", "init", "--cone"],
        cwd=ROOT,
    )
    run(
        ["git", "-C", "ast/grammars/tree-sitter-kotlin", "sparse-checkout", "set", "src"],
        cwd=ROOT,
    )
    run(
        ["git", "-C", "ast/grammars/tree-sitter-swift", "sparse-checkout", "init", "--cone"],
        cwd=ROOT,
    )
    run(
        ["git", "-C", "ast/grammars/tree-sitter-swift", "sparse-checkout", "set", "src"],
        cwd=ROOT,
    )
    # tree-sitter-swift does not commit parser.c or tree_sitter/ headers;
    # download pre-generated files from release tarball
    print("  Downloading tree-sitter-swift sources from release tarball...")
    swift_src = ROOT / "ast/grammars/tree-sitter-swift/src"
    (swift_src / "tree_sitter").mkdir(exist_ok=True)
    extract = {
        "./src/parser.c": swift_src / "parser.c",
        "./src/tree_sitter/parser.h": swift_src / "tree_sitter/parser.h",
        "./src/tree_sitter/alloc.h": swift_src / "tree_sitter/alloc.h",
        "./src/tree_sitter/array.h": swift_src / "tree_sitter/array.h",
    }
    with urllib.request.urlopen(SWIFT_PARSER_URL) as resp:
        with tarfile.open(fileobj=io.BytesIO(resp.read()), mode="r:gz") as tar:
            for member_name, dest in extract.items():
                f = tar.extractfile(tar.getmember(member_name))
                dest.write_bytes(f.read())
    print("  tree-sitter-swift sources downloaded.")
    run(
        ["git", "-C", "ast/grammars/tree-sitter-lua", "sparse-checkout", "init", "--cone"],
        cwd=ROOT,
    )
    run(
        ["git", "-C", "ast/grammars/tree-sitter-lua", "sparse-checkout", "set", "src"],
        cwd=ROOT,
    )
    print("Submodules initialized.")


def build():
    print("\n==> Building release binary...")
    run(["zig", "build", "-Doptimize=ReleaseFast"], cwd=ROOT)
    print("Build complete.")


def test():
    print("\n==> Running tests...")
    CACHE.mkdir(exist_ok=True)

    for src, obj in TS_C_SOURCES:
        run(
            ["zig", "cc", "-c", "-std=gnu11"]
            + TS_INCLUDE_FLAGS
            + [str(src), "-o", str(obj)],
            cwd=ROOT,
        )

    all_objs = [str(obj) for _, obj in TS_C_SOURCES]
    run(["zig", "ar", "rcs", str(CACHE / "ts_ast.a")] + all_objs, cwd=ROOT)

    run(
        [
            "zig",
            "test",
            "-lc",
            "--dep",
            "options",
            "-Mroot=src/root.zig",
            "-Moptions=src/cli/version/fallback.zig",
            str(CACHE / "ts_ast.a"),
        ],
        cwd=ROOT,
    )
    print("Tests passed.")


def main():
    commands = sys.argv[1:] or ["init", "build"]

    valid = {"init", "build", "test", "all"}
    for cmd in commands:
        if cmd not in valid:
            print(f"Unknown command: {cmd!r}")
            print(f"Valid commands: {', '.join(sorted(valid))}")
            sys.exit(1)

    check_deps()

    steps = ["init", "build", "test"] if "all" in commands else commands
    dispatch = {"init": init, "build": build, "test": test}
    for step in steps:
        dispatch[step]()

    print("\nDone.")


if __name__ == "__main__":
    main()
