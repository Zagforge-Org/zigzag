.PHONY: build init test run compile_commands

TS_SRC   := ast/vendor/tree-sitter/lib/src
TS_FLAGS := -std=gnu11 \
	-Iast/vendor/tree-sitter/lib/include \
	-Iast/vendor/tree-sitter/lib/src \
	-Iast/src \
	-Iast/grammars/tree-sitter-python/src \
	-Iast/grammars/tree-sitter-javascript/src \
	-Iast/grammars/tree-sitter-zig/src \
	-Iast/grammars/tree-sitter-typescript/typescript/src \
	-Iast/grammars/tree-sitter-typescript/tsx/src \
	-Iast/grammars/tree-sitter-rust/src \
	-Iast/grammars/tree-sitter-go/src \
	-Iast/grammars/tree-sitter-c/src \
	-Iast/grammars/tree-sitter-cpp/src \
	-Iast/grammars/tree-sitter-java/src \
	-Iast/grammars/tree-sitter-c-sharp/src

TS_OBJS := \
	.zig-cache/ts_alloc.o .zig-cache/ts_get_changed_ranges.o \
	.zig-cache/ts_language.o .zig-cache/ts_lexer.o \
	.zig-cache/ts_node.o .zig-cache/ts_parser.o \
	.zig-cache/ts_query.o .zig-cache/ts_stack.o \
	.zig-cache/ts_subtree.o .zig-cache/ts_tree_cursor.o \
	.zig-cache/ts_tree.o .zig-cache/ts_wasm_store.o \
	.zig-cache/ts_py_parser.o .zig-cache/ts_py_scanner.o \
	.zig-cache/ts_js_parser.o .zig-cache/ts_js_scanner.o \
	.zig-cache/ts_zig_parser.o \
	.zig-cache/ts_ts_parser.o .zig-cache/ts_ts_scanner.o \
	.zig-cache/ts_tsx_parser.o .zig-cache/ts_tsx_scanner.o \
	.zig-cache/ts_rust_parser.o .zig-cache/ts_rust_scanner.o \
	.zig-cache/ts_go_parser.o \
	.zig-cache/ts_c_parser.o \
	.zig-cache/ts_cpp_parser.o .zig-cache/ts_cpp_scanner.o \
	.zig-cache/ts_java_parser.o \
	.zig-cache/ts_cs_parser.o .zig-cache/ts_cs_scanner.o \
	.zig-cache/ts_chunker.o

init:
	git submodule update --init --depth 1
	git -C ast/vendor/tree-sitter sparse-checkout init --cone
	git -C ast/vendor/tree-sitter sparse-checkout set lib
	git -C ast/grammars/tree-sitter-python sparse-checkout init --cone
	git -C ast/grammars/tree-sitter-python sparse-checkout set src
	git -C ast/grammars/tree-sitter-javascript sparse-checkout init --cone
	git -C ast/grammars/tree-sitter-javascript sparse-checkout set src
	git -C ast/grammars/tree-sitter-zig sparse-checkout init --cone
	git -C ast/grammars/tree-sitter-zig sparse-checkout set src
	git -C ast/grammars/tree-sitter-typescript sparse-checkout init --cone
	git -C ast/grammars/tree-sitter-typescript sparse-checkout set typescript/src tsx/src common
	git -C ast/grammars/tree-sitter-rust sparse-checkout init --cone
	git -C ast/grammars/tree-sitter-rust sparse-checkout set src
	git -C ast/grammars/tree-sitter-go sparse-checkout init --cone
	git -C ast/grammars/tree-sitter-go sparse-checkout set src
	git -C ast/grammars/tree-sitter-c sparse-checkout init --cone
	git -C ast/grammars/tree-sitter-c sparse-checkout set src
	git -C ast/grammars/tree-sitter-cpp sparse-checkout init --cone
	git -C ast/grammars/tree-sitter-cpp sparse-checkout set src
	git -C ast/grammars/tree-sitter-java sparse-checkout init --cone
	git -C ast/grammars/tree-sitter-java sparse-checkout set src
	git -C ast/grammars/tree-sitter-c-sharp sparse-checkout init --cone
	git -C ast/grammars/tree-sitter-c-sharp sparse-checkout set src

build:
	zig build -Doptimize=ReleaseFast

test:
	mkdir -p .zig-cache
	zig cc -c $(TS_FLAGS) $(TS_SRC)/alloc.c              -o .zig-cache/ts_alloc.o
	zig cc -c $(TS_FLAGS) $(TS_SRC)/get_changed_ranges.c -o .zig-cache/ts_get_changed_ranges.o
	zig cc -c $(TS_FLAGS) $(TS_SRC)/language.c           -o .zig-cache/ts_language.o
	zig cc -c $(TS_FLAGS) $(TS_SRC)/lexer.c              -o .zig-cache/ts_lexer.o
	zig cc -c $(TS_FLAGS) $(TS_SRC)/node.c               -o .zig-cache/ts_node.o
	zig cc -c $(TS_FLAGS) $(TS_SRC)/parser.c             -o .zig-cache/ts_parser.o
	zig cc -c $(TS_FLAGS) $(TS_SRC)/query.c              -o .zig-cache/ts_query.o
	zig cc -c $(TS_FLAGS) $(TS_SRC)/stack.c              -o .zig-cache/ts_stack.o
	zig cc -c $(TS_FLAGS) $(TS_SRC)/subtree.c            -o .zig-cache/ts_subtree.o
	zig cc -c $(TS_FLAGS) $(TS_SRC)/tree_cursor.c        -o .zig-cache/ts_tree_cursor.o
	zig cc -c $(TS_FLAGS) $(TS_SRC)/tree.c               -o .zig-cache/ts_tree.o
	zig cc -c $(TS_FLAGS) $(TS_SRC)/wasm_store.c         -o .zig-cache/ts_wasm_store.o
	zig cc -c $(TS_FLAGS) ast/grammars/tree-sitter-python/src/parser.c      -o .zig-cache/ts_py_parser.o
	zig cc -c $(TS_FLAGS) ast/grammars/tree-sitter-python/src/scanner.c     -o .zig-cache/ts_py_scanner.o
	zig cc -c $(TS_FLAGS) ast/grammars/tree-sitter-javascript/src/parser.c  -o .zig-cache/ts_js_parser.o
	zig cc -c $(TS_FLAGS) ast/grammars/tree-sitter-javascript/src/scanner.c -o .zig-cache/ts_js_scanner.o
	zig cc -c $(TS_FLAGS) ast/grammars/tree-sitter-zig/src/parser.c                          -o .zig-cache/ts_zig_parser.o
	zig cc -c $(TS_FLAGS) ast/grammars/tree-sitter-typescript/typescript/src/parser.c        -o .zig-cache/ts_ts_parser.o
	zig cc -c $(TS_FLAGS) ast/grammars/tree-sitter-typescript/typescript/src/scanner.c       -o .zig-cache/ts_ts_scanner.o
	zig cc -c $(TS_FLAGS) ast/grammars/tree-sitter-typescript/tsx/src/parser.c               -o .zig-cache/ts_tsx_parser.o
	zig cc -c $(TS_FLAGS) ast/grammars/tree-sitter-typescript/tsx/src/scanner.c              -o .zig-cache/ts_tsx_scanner.o
	zig cc -c $(TS_FLAGS) ast/grammars/tree-sitter-rust/src/parser.c                        -o .zig-cache/ts_rust_parser.o
	zig cc -c $(TS_FLAGS) ast/grammars/tree-sitter-rust/src/scanner.c                       -o .zig-cache/ts_rust_scanner.o
	zig cc -c $(TS_FLAGS) ast/grammars/tree-sitter-go/src/parser.c                         -o .zig-cache/ts_go_parser.o
	zig cc -c $(TS_FLAGS) ast/grammars/tree-sitter-c/src/parser.c                          -o .zig-cache/ts_c_parser.o
	zig cc -c $(TS_FLAGS) ast/grammars/tree-sitter-cpp/src/parser.c                       -o .zig-cache/ts_cpp_parser.o
	zig cc -c $(TS_FLAGS) ast/grammars/tree-sitter-cpp/src/scanner.c                      -o .zig-cache/ts_cpp_scanner.o
	zig cc -c $(TS_FLAGS) ast/grammars/tree-sitter-java/src/parser.c                      -o .zig-cache/ts_java_parser.o
	zig cc -c $(TS_FLAGS) ast/grammars/tree-sitter-c-sharp/src/parser.c                   -o .zig-cache/ts_cs_parser.o
	zig cc -c $(TS_FLAGS) ast/grammars/tree-sitter-c-sharp/src/scanner.c                  -o .zig-cache/ts_cs_scanner.o
	zig cc -c $(TS_FLAGS) ast/src/chunker.c                                                  -o .zig-cache/ts_chunker.o
	zig ar rcs .zig-cache/ts_ast.a $(TS_OBJS)
	zig test -lc --dep options -Mroot=src/root.zig -Moptions=src/cli/version/fallback.zig .zig-cache/ts_ast.a

run:
	zig run --dep options -Mroot=src/main.zig -Moptions=src/cli/version/fallback.zig -- $(filter-out $@,$(MAKECMDGOALS))

compile_commands:
	cmake -S ast -B ast/build
	ln -sf ast/build/compile_commands.json ast/compile_commands.json

%:
	@:
