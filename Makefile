.PHONY: build init test run compile_commands

AST_CFLAGS := -std=gnu99 \
	-Iast/vendor/tree-sitter/include \
	-Iast/vendor/tree-sitter/src \
	-Iast/src \
	-Iast/grammars/tree-sitter-python/src

init:
	git submodule update --init --recursive

build:
	zig build -Doptimize=ReleaseFast

test:
	mkdir -p .zig-cache
	zig cc -c $(AST_CFLAGS) ast/vendor/tree-sitter/src/lib.c -o .zig-cache/ts_lib.o
	zig cc -c $(AST_CFLAGS) ast/grammars/tree-sitter-python/src/parser.c -o .zig-cache/ts_parser.o
	zig cc -c $(AST_CFLAGS) ast/grammars/tree-sitter-python/src/scanner.c -o .zig-cache/ts_scanner.o
	zig cc -c $(AST_CFLAGS) ast/src/chunker.c -o .zig-cache/ts_chunker.o
	zig ar rcs .zig-cache/ts_ast.a .zig-cache/ts_lib.o .zig-cache/ts_parser.o .zig-cache/ts_scanner.o .zig-cache/ts_chunker.o
	zig test -lc --dep options -Mroot=src/root.zig -Moptions=src/cli/version/fallback.zig .zig-cache/ts_ast.a

run:
	zig run --dep options -Mroot=src/main.zig -Moptions=src/cli/version/fallback.zig -- $(filter-out $@,$(MAKECMDGOALS))

compile_commands:
	cmake -S ast -B ast/build
	ln -sf ast/build/compile_commands.json ast/compile_commands.json

%:
	@:
