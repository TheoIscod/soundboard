# Only the Command Line Tools are installed: Swift Testing ships there but
# outside the default search paths, so tests need them passed explicitly.
# With full Xcode, plain `swift test` works and these flags are harmless.
CLT_DEV := /Library/Developer/CommandLineTools/Library/Developer
TEST_FLAGS := -Xswiftc -F$(CLT_DEV)/Frameworks \
	-Xlinker -F$(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/usr/lib

.PHONY: build run test lint format check

build:
	swift build

run:
	swift run Soundboard

test:
	swift test $(TEST_FLAGS)

lint:
	swift format lint --strict --recursive Package.swift Sources Tests

format:
	swift format format --in-place --recursive Package.swift Sources Tests

check: lint build test
