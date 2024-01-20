all: fmt build test

dev: fmt test

build:
	zig build --prefix bin/win -Doptimize=ReleaseSafe -Dtarget=x86_64-windows
	zig build --prefix bin/lin -Doptimize=ReleaseSafe -Dtarget=x86_64-linux

fmt:
	zig fmt src
	zig fmt build.zig

test:
	zig build test

benchmarks-sha1:
	zig build -Doptimize=ReleaseSafe benchmarks -- -iter=100 sha1:big sha1-ref:big sha1:small

benchmarks-zlib:
	zig build benchmarks -Doptimize=ReleaseSafe -- -iter=100 zlib:decompress zlib-ref:decompress

TEST_DOCKER_IMAGE=zit-test
TEST_DOCKER_MOUNT_CMD=-v $(CURDIR)/bin/:/workspace/bin:ro -v $(CURDIR)/cram-tests:/workspace/cram-tests

test-cram:
	docker run -w /workspace $(TEST_DOCKER_MOUNT_CMD) $(TEST_DOCKER_IMAGE) make -C cram-tests PROMOTE=$(PROMOTE) test

test-image-build:
	docker build -t $(TEST_DOCKER_IMAGE) .

test-shell:
	docker run -it -w /workspace --entrypoint bash $(TEST_DOCKER_MOUNT_CMD) $(TEST_DOCKER_IMAGE)
