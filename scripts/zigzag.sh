#!/bin/bash

cd ..

make build

cd zig-out/bin

sudo mv zigzag /usr/local/bin
