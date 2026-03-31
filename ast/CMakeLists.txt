cmake_minimum_required(VERSION 3.15)
project(tree-sitter-py C)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/bin)

add_subdirectory(vendor/tree-sitter)

add_library(tree-sitter-python
    grammars/tree-sitter-python/src/parser.c
    grammars/tree-sitter-python/src/scanner.c
)

set_target_properties(tree-sitter-python PROPERTIES C_STANDARD 99)

target_include_directories(tree-sitter-python
    PRIVATE grammars/tree-sitter-python/src
)

add_library(tree-sitter-javascript
    grammars/tree-sitter-javascript/src/parser.c
    grammars/tree-sitter-javascript/src/scanner.c
)

set_target_properties(tree-sitter-javascript PROPERTIES C_STANDARD 99)

target_include_directories(tree-sitter-javascript
    PRIVATE grammars/tree-sitter-javascript/src
)

add_library(tree-sitter-zig
    grammars/tree-sitter-zig/src/parser.c
)

set_target_properties(tree-sitter-zig PROPERTIES C_STANDARD 99)

target_include_directories(tree-sitter-zig
    PRIVATE grammars/tree-sitter-zig/src
)

add_library(tree-sitter-typescript
    grammars/tree-sitter-typescript/typescript/src/parser.c
    grammars/tree-sitter-typescript/typescript/src/scanner.c
)

set_target_properties(tree-sitter-typescript PROPERTIES C_STANDARD 99)

target_include_directories(tree-sitter-typescript
    PRIVATE grammars/tree-sitter-typescript/typescript/src
)

add_library(tree-sitter-tsx
    grammars/tree-sitter-typescript/tsx/src/parser.c
    grammars/tree-sitter-typescript/tsx/src/scanner.c
)

set_target_properties(tree-sitter-tsx PROPERTIES C_STANDARD 99)

target_include_directories(tree-sitter-tsx
    PRIVATE grammars/tree-sitter-typescript/tsx/src
)

add_library(tree-sitter-rust
    grammars/tree-sitter-rust/src/parser.c
    grammars/tree-sitter-rust/src/scanner.c
)

set_target_properties(tree-sitter-rust PROPERTIES C_STANDARD 99)

target_include_directories(tree-sitter-rust
    PRIVATE grammars/tree-sitter-rust/src
)

add_library(tree-sitter-go
    grammars/tree-sitter-go/src/parser.c
)

set_target_properties(tree-sitter-go PROPERTIES C_STANDARD 99)

target_include_directories(tree-sitter-go
    PRIVATE grammars/tree-sitter-go/src
)

add_library(tree-sitter-c
    grammars/tree-sitter-c/src/parser.c
)

set_target_properties(tree-sitter-c PROPERTIES C_STANDARD 99)

target_include_directories(tree-sitter-c
    PRIVATE grammars/tree-sitter-c/src
)

add_library(tree-sitter-cpp
    grammars/tree-sitter-cpp/src/parser.c
    grammars/tree-sitter-cpp/src/scanner.c
)

set_target_properties(tree-sitter-cpp PROPERTIES C_STANDARD 99)

target_include_directories(tree-sitter-cpp
    PRIVATE grammars/tree-sitter-cpp/src
)

add_library(tree-sitter-java
    grammars/tree-sitter-java/src/parser.c
)

set_target_properties(tree-sitter-java PROPERTIES C_STANDARD 99)

target_include_directories(tree-sitter-java
    PRIVATE grammars/tree-sitter-java/src
)

add_executable(ast-parser src/main.c src/file_reader.c src/chunker.c)
target_link_libraries(ast-parser PRIVATE tree-sitter tree-sitter-python tree-sitter-javascript tree-sitter-zig tree-sitter-typescript tree-sitter-tsx tree-sitter-rust tree-sitter-go tree-sitter-c tree-sitter-cpp tree-sitter-java)