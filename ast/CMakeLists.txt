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

add_executable(ast-parser src/main.c src/file_reader.c src/chunker.c)
target_link_libraries(ast-parser PRIVATE tree-sitter tree-sitter-python tree-sitter-javascript)