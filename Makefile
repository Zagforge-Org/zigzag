.PHONY: build

build:
	echo "Building project..."
	zig build -Doptimize=ReleaseFast
