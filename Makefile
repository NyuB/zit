all: fmt build test
build:
	zig build
fmt:
	zig fmt src
	zig fmt build.zig

test:
	zig build test

benchmarks:
	zig build -Doptimize=ReleaseSafe benchmarks -- sha1:big sha1:small