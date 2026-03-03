.PHONY: build test

build:
	echo "Building project..."
	zig build -Doptimize=ReleaseFast

test:
	zig test src/root.zig
