cmake_minimum_required(VERSION 3.15)
project(tree-sitter C)

add_library(tree-sitter
    src/lib.c
)

target_include_directories(tree-sitter
    PUBLIC include
    PRIVATE src
)

set_target_properties(tree-sitter PROPERTIES C_STANDARD 99)
