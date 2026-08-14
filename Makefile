.PHONY: build test app run icon clean

build:
	swift build

test:
	swift test

app:
	./scripts/build-app.sh release

icon:
	rm -rf build/AppIcon.iconset
	mkdir -p build/AppIcon.iconset
	for s in 16 32 128 256 512; do \
		swift scripts/render-icon.swift default $$s build/AppIcon.iconset/icon_$${s}x$${s}.png; \
		swift scripts/render-icon.swift default $$((s*2)) build/AppIcon.iconset/icon_$${s}x$${s}@2x.png; \
	done
	iconutil -c icns build/AppIcon.iconset -o Packaging/AppIcon.icns

run:
	swift run MaxCLI

clean:
	swift package clean
