all: fmt build test
build:
	zig build
fmt:
	zig fmt src
	zig fmt build.zig

test:
	zig build test

run:
	zig build run

explore:
	zig test src/explore.zig