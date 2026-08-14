#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
CONFIGURATION=${1:-release}
OUTPUT_DIR="$PROJECT_DIR/build"
APP_DIR="$OUTPUT_DIR/MaxCLI.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$PROJECT_DIR"
swift build -c "$CONFIGURATION"
BIN_DIR=$(swift build -c "$CONFIGURATION" --show-bin-path)

if [[ "$APP_DIR" != "$PROJECT_DIR/build/MaxCLI.app" ]]; then
    print -u2 "Refusing unexpected output path: $APP_DIR"
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_DIR/MaxCLI" "$MACOS_DIR/MaxCLI"
cp "$PROJECT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Packaging/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

# SwiftTerm explicitly probes the standard macOS app resource location.
if [[ -d "$BIN_DIR/SwiftTerm_SwiftTerm.bundle" ]]; then
    cp -R "$BIN_DIR/SwiftTerm_SwiftTerm.bundle" "$RESOURCES_DIR/SwiftTerm_SwiftTerm.bundle"
fi

# Localizations are bundled next to the binary by SwiftPM.
if [[ -d "$BIN_DIR/MaxCLI_MaxCLI.bundle" ]]; then
    cp -R "$BIN_DIR/MaxCLI_MaxCLI.bundle" "$RESOURCES_DIR/MaxCLI_MaxCLI.bundle"
fi

codesign --force --deep --sign - "$APP_DIR"
print "Built $APP_DIR"
