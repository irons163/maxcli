.PHONY: build test app run clean

build:
	swift build

test:
	swift test

app:
	./scripts/build-app.sh release

run:
	swift run MaxCLI

clean:
	swift package clean
