all: fmt build test

dev: fmt test

build:
	zig build -Doptimize=ReleaseSafe

fmt:
	zig fmt src
	zig fmt build.zig

test:
	zig build test

benchmarks-sha1:
	zig build -Doptimize=ReleaseSafe benchmarks -- -iter=100 sha1:big sha1-ref:big sha1:small

benchmarks-zlib:
	zig build benchmarks -Doptimize=ReleaseSafe -- -iter=100 zlib:decompress zlib-ref:decompress