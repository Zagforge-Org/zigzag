.PHONY: build test run compile_commands

build:
	echo "Building project..."
	zig build -Doptimize=ReleaseFast

test:
	zig test --dep options -Mroot=src/root.zig -Moptions=src/cli/version/fallback.zig

run:
	zig run --dep options -Mroot=src/main.zig -Moptions=src/cli/version/fallback.zig -- $(filter-out $@,$(MAKECMDGOALS))

compile_commands:
	cmake -S ast -B ast/build
	ln -sf ast/build/compile_commands.json ast/compile_commands.json

%:
	@:
