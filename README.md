# Zit

Exploring Zig by implementing some git components

## Currently implemented

+ SHA1
+ Myers diff (non-linear 'naive' version)
+ zlib decompression

## Requirements
+ [Zig](https://ziglang.org/)
+ [make](https://www.gnu.org/software/make/) if you want to avoid running everything manually. For Windows users there is [mingw-make](https://www.mingw-w64.org/) 
+ [Cram](https://bitheap.org/cram/) or [Docker](https://www.docker.com/) (mandatory for Windows users) to run the end-to-end tests

## Developing

### Compile the project
`make build`

### Run Zig unit tests
`make test`

### Run end to end tests with cram
`make -C cram-tests test`

### Run end-to-end tests in docker
+ (Once) build the docker image: `make test-image-build`
+ run the test suite: `make test-cram`
