# Only the Command Line Tools are installed: Swift Testing ships there but
# outside the default search paths, so tests need them passed explicitly.
# With full Xcode, plain `swift test` works and these flags are harmless.
CLT_DEV := /Library/Developer/CommandLineTools/Library/Developer
TEST_FLAGS := -Xswiftc -F$(CLT_DEV)/Frameworks \
	-Xlinker -F$(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/usr/lib

APP := build/Soundboard.app

.PHONY: build run test lint format check icon bundle open

build:
	swift build

run:
	swift run Soundboard

test:
	swift test $(TEST_FLAGS)

lint:
	swift format lint --strict --recursive Package.swift Sources Tests scripts

format:
	swift format format --in-place --recursive Package.swift Sources Tests scripts

check: lint build test

# Regenerates the committed Resources/AppIcon.icns from scripts/make-icon.swift.
icon:
	mkdir -p build/AppIcon.iconset
	swift scripts/make-icon.swift build/AppIcon-1024.png
	for size in 16 32 128 256 512; do \
		sips -z $$size $$size build/AppIcon-1024.png --out build/AppIcon.iconset/icon_$${size}x$${size}.png >/dev/null; \
		double=$$((size * 2)); \
		sips -z $$double $$double build/AppIcon-1024.png --out build/AppIcon.iconset/icon_$${size}x$${size}@2x.png >/dev/null; \
	done
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns

# Release build wrapped in an app bundle, signed ad hoc so macOS runs it locally.
bundle:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp "$$(swift build -c release --show-bin-path)/Soundboard" $(APP)/Contents/MacOS/
	cp Resources/Info.plist $(APP)/Contents/
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/
	cp -R Resources/fr.lproj $(APP)/Contents/Resources/
	codesign --force --sign - $(APP)

open: bundle
	open $(APP)

