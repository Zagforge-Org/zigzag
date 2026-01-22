#!/usr/bin/env bash
set -e

ROOT_DIR="test_data"

echo "Creating test folder structure in '$ROOT_DIR'..."

# Remove old folder if it exists
rm -rf "$ROOT_DIR"

# Create root and subdirectories
mkdir -p "$ROOT_DIR/small_files"
mkdir -p "$ROOT_DIR/medium_files"
mkdir -p "$ROOT_DIR/large_files/subdir1"
mkdir -p "$ROOT_DIR/large_files/subdir2"

echo "Generating small text files (1 KB each)..."
for i in $(seq 1 5); do
    head -c 1024 </dev/urandom | base64 > "$ROOT_DIR/small_files/file_$i.txt"
done

echo "Generating medium text files (1 MB each)..."
for i in $(seq 1 3); do
    head -c $((1024 * 1024)) </dev/urandom | base64 > "$ROOT_DIR/medium_files/file_$i.txt"
done

echo "Generating large files (16 MB each)..."
for i in $(seq 1 2); do
    head -c $((16 * 1024 * 1024)) </dev/urandom | base64 > "$ROOT_DIR/large_files/subdir1/large_$i.bin"
    head -c $((16 * 1024 * 1024)) </dev/urandom | base64 > "$ROOT_DIR/large_files/subdir2/large_$i.bin"
done

echo "Creating a few empty files..."
touch "$ROOT_DIR/empty1.txt"
touch "$ROOT_DIR/large_files/subdir1/empty2.txt"

echo "Test structure created!"
tree "$ROOT_DIR" || ls -R "$ROOT_DIR"
