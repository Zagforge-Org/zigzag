.PHONY: build test run

build:
	echo "Building project..."
	zig build -Doptimize=ReleaseFast

test:
	zig test --dep options -Mroot=src/root.zig -Moptions=src/cli/options_fallback.zig

run:
	zig run --dep options -Mroot=src/main.zig -Moptions=src/cli/options_fallback.zig -- $(filter-out $@,$(MAKECMDGOALS))

%:
	@:
