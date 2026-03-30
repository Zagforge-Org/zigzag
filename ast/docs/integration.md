# AST Chunker — Integration Guide for ZigZag

This library parses source code files using [tree-sitter](https://tree-sitter.github.io/tree-sitter/) and extracts top-level semantic chunks (functions, classes, decorated definitions) as line ranges. It is designed to be called from Zig via C interop.

---

## Project Structure

```
vendor/tree-sitter/        tree-sitter runtime
grammars/                  language grammars
  tree-sitter-python/
src/
  file_reader.h/c          reads a file into a buffer
  chunker.h/c              parses source and extracts chunks
  main.c                   example usage
```

---

## Building

```bash
cmake -S . -B build
cmake --build build
```

The binary is output to `bin/ast-parser`. `compile_commands.json` is symlinked to the project root for editor tooling.

Or use the Makefile:

```bash
make build
make clean
```

---

## API

### `file_reader.h`

```c
char *read_file(const char *filename);
```

Reads the entire contents of `filename` into a null-terminated heap-allocated buffer. Returns `NULL` on failure. The caller is responsible for freeing the returned buffer.

---

### `chunker.h`

#### Types

```c
typedef struct {
    uint32_t start_line;  // 1-based
    uint32_t end_line;    // 1-based, inclusive
} Chunk;

typedef struct {
    const char **node_types;    // array of tree-sitter node type strings
    uint32_t node_type_count;
} ChunkConfig;

typedef struct {
    Chunk   *chunks;
    uint32_t count;
} ChunkResult;
```

#### Functions

```c
ChunkResult extract_chunks(
    const TSLanguage *language,
    const ChunkConfig *config,
    const char *source,
    uint32_t length
);
```

Parses `source` using the given `language` grammar and returns all top-level nodes whose type matches any entry in `config->node_types`. Line numbers are 1-based.

```c
void free_chunk_result(ChunkResult result);
```

Frees the `chunks` array inside `result`. Must be called after you are done with the result.

---

## Usage from C

```c
#include "file_reader.h"
#include "chunker.h"

extern const TSLanguage *tree_sitter_python(void);

const char *python_types[] = {
    "function_definition",
    "class_definition",
    "decorated_definition"
};

ChunkConfig config = {
    .node_types      = python_types,
    .node_type_count = 3
};

char *source = read_file("main.py");
ChunkResult result = extract_chunks(tree_sitter_python(), &config, source, strlen(source));

for (uint32_t i = 0; i < result.count; i++) {
    printf("lines %u-%u\n", result.chunks[i].start_line, result.chunks[i].end_line);
}

free_chunk_result(result);
free(source);
```

---

## Usage from Zig

```zig
const c = @cImport({
    @cInclude("chunker.h");
    @cInclude("file_reader.h");
});

extern fn tree_sitter_python() *const c.TSLanguage;

const python_types = [_][*:0]const u8{
    "function_definition",
    "class_definition",
    "decorated_definition",
};

const config = c.ChunkConfig{
    .node_types      = &python_types,
    .node_type_count = python_types.len,
};

const source = c.read_file("main.py");
defer std.c.free(source);

const result = c.extract_chunks(tree_sitter_python(), &config, source, std.mem.len(source));
defer c.free_chunk_result(result);

for (result.chunks[0..result.count]) |chunk| {
    std.debug.print("lines {}-{}\n", .{ chunk.start_line, chunk.end_line });
}
```

---

## Adding a Language

1. Add the grammar source to `grammars/<name>/`
2. Add it to `CMakeLists.txt`:
   ```cmake
   add_library(tree-sitter-<name>
       grammars/<name>/src/parser.c
       grammars/<name>/src/scanner.c  # if present
   )
   set_target_properties(tree-sitter-<name> PROPERTIES C_STANDARD 99)
   target_include_directories(tree-sitter-<name> PRIVATE grammars/<name>/src)
   target_link_libraries(ast-parser PRIVATE tree-sitter-<name>)
   ```
3. Declare the language function in your caller:
   ```c
   extern const TSLanguage *tree_sitter_<name>(void);
   ```
4. Define the node types to chunk on for that language and pass them in via `ChunkConfig`

### Common node types by language

| Language   | Node types |
|------------|-----------|
| Python     | `function_definition`, `class_definition`, `decorated_definition` |
| JavaScript | `function_declaration`, `class_declaration`, `arrow_function` |
| TypeScript | `function_declaration`, `class_declaration`, `method_definition` |
| Rust       | `function_item`, `impl_item`, `struct_item` |
| Go         | `function_declaration`, `method_declaration`, `type_declaration` |
| C/C++      | `function_definition`, `struct_specifier`, `class_specifier` |

---

## Notes

- `extract_chunks` only walks **top-level** nodes. Nested functions inside classes are not captured.
- Line numbers are **1-based** and **inclusive** on both ends.
- Memory ownership: `ChunkResult.chunks` is heap-allocated by the library. Always call `free_chunk_result` when done.
