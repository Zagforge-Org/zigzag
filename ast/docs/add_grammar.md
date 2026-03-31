# Adding a New Tree-Sitter Grammar

When adding support for a new language, update all of the following:

## 1. Git submodule

```sh
git submodule add --depth 1 https://github.com/tree-sitter/tree-sitter-<lang> ast/grammars/tree-sitter-<lang>
```

## 2. `ast/CMakeLists.txt`

Add a library target and link it to `ast-parser`:

```cmake
add_library(tree-sitter-<lang>
    grammars/tree-sitter-<lang>/src/parser.c
    grammars/tree-sitter-<lang>/src/scanner.c
)

set_target_properties(tree-sitter-<lang> PROPERTIES C_STANDARD 99)

target_include_directories(tree-sitter-<lang>
    PRIVATE grammars/tree-sitter-<lang>/src
)
```

And append `tree-sitter-<lang>` to the `target_link_libraries` line.

## 3. `build.zig`

In both the main `mod` and `test_mod` blocks, add the grammar sources and include path:

```zig
// inside addCSourceFiles .files
"grammars/tree-sitter-<lang>/src/parser.c",
"grammars/tree-sitter-<lang>/src/scanner.c",

// include path
mod.addIncludePath(b.path("ast/grammars/tree-sitter-<lang>/src"));
```

## 4. `scripts/setup.py`

Add the include flag:

```python
"-Iast/grammars/tree-sitter-<lang>/src",
```

Add the C sources:

```python
(ROOT / "ast/grammars/tree-sitter-<lang>/src/parser.c",  CACHE / "ts_<lang>_parser.o"),
(ROOT / "ast/grammars/tree-sitter-<lang>/src/scanner.c", CACHE / "ts_<lang>_scanner.o"),
```

Add sparse-checkout in `init()`:

```python
run(["git", "-C", "ast/grammars/tree-sitter-<lang>", "sparse-checkout", "init", "--cone"], cwd=ROOT)
run(["git", "-C", "ast/grammars/tree-sitter-<lang>", "sparse-checkout", "set", "src"], cwd=ROOT)
```

## 5. `Makefile`

Add the include flag to `TS_FLAGS`, the `.o` files to `TS_OBJS`, the `zig cc` compile steps in `test`, and the sparse-checkout in `init`:

```makefile
# TS_FLAGS
-Iast/grammars/tree-sitter-<lang>/src

# TS_OBJS
.zig-cache/ts_<lang>_parser.o .zig-cache/ts_<lang>_scanner.o

# test target
zig cc -c $(TS_FLAGS) ast/grammars/tree-sitter-<lang>/src/parser.c  -o .zig-cache/ts_<lang>_parser.o
zig cc -c $(TS_FLAGS) ast/grammars/tree-sitter-<lang>/src/scanner.c -o .zig-cache/ts_<lang>_scanner.o

# init target
git -C ast/grammars/tree-sitter-<lang> sparse-checkout init --cone
git -C ast/grammars/tree-sitter-<lang> sparse-checkout set src
```

## 6. `.github/workflows/ci.yml`

In both the `test` and `build` jobs, add the sparse-checkout lines, the include flag in `F`, the two `zig cc` compile steps, and the two `.o` files in the `zig ar` invocation.

## 7. `src/cli/commands/report/writers/llm/ast_chunker.zig`

Add the extern declaration, node types, and extension mapping:

```zig
extern fn tree_sitter_<lang>() *const TSLanguage;

const <lang>_types = [_][*c]const u8{
    // top-level node type names from the grammar
};
```

In `languageConfig`, add a branch for the relevant file extensions:

```zig
if (std.mem.eql(u8, e, "<ext>")) {
    return .{
        .language = tree_sitter_<lang>(),
        .node_types = &<lang>_types,
    };
}
```
