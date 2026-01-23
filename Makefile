.PHONY: build test clean

build:
	echo "Building project..."
	zig build -Doptimize=ReleaseFast
