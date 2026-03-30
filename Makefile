.PHONY: build test run compile_commands

build:
	echo "Building project..."
	zig build -Doptimize=ReleaseFast

test:
	zig test -lc --dep options -Mroot=src/root.zig -Moptions=src/cli/version/fallback.zig \
		-Iast/vendor/tree-sitter/include -Iast/src -Iast/grammars/tree-sitter-python/src \
		-cflags -std=gnu99 -- \
		ast/vendor/tree-sitter/src/lib.c \
		ast/grammars/tree-sitter-python/src/parser.c \
		ast/grammars/tree-sitter-python/src/scanner.c \
		ast/src/chunker.c

run:
	zig run --dep options -Mroot=src/main.zig -Moptions=src/cli/version/fallback.zig -- $(filter-out $@,$(MAKECMDGOALS))

compile_commands:
	cmake -S ast -B ast/build
	ln -sf ast/build/compile_commands.json ast/compile_commands.json

%:
	@:
