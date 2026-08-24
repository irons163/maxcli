#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
CONFIGURATION=${1:-release}
BUILD_TRIPLE="${BUILD_TRIPLE:-}"
APP_VERSION="${APP_VERSION:-}"
APP_BUILD_VERSION="${APP_BUILD_VERSION:-}"
OUTPUT_DIR="$PROJECT_DIR/build"
APP_DIR="$OUTPUT_DIR/MaxCLI.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"

cd "$PROJECT_DIR"
SWIFT_BUILD_ARGS=()
if [[ -n "$BUILD_TRIPLE" ]]; then
    SWIFT_BUILD_ARGS+=(--triple "$BUILD_TRIPLE")
fi

swift build -c "$CONFIGURATION" "${SWIFT_BUILD_ARGS[@]}"
BIN_DIR=$(swift build -c "$CONFIGURATION" "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)

if [[ "$APP_DIR" != "$PROJECT_DIR/build/MaxCLI.app" ]]; then
    print -u2 "Refusing unexpected output path: $APP_DIR"
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"
cp "$BIN_DIR/MaxCLI" "$MACOS_DIR/MaxCLI"
cp "$PROJECT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Packaging/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

if [[ -n "$APP_VERSION" ]]; then
    plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$CONTENTS_DIR/Info.plist"
fi
if [[ -n "$APP_BUILD_VERSION" ]]; then
    plutil -replace CFBundleVersion -string "$APP_BUILD_VERSION" "$CONTENTS_DIR/Info.plist"
fi

if [[ ! -d "$BIN_DIR/Sparkle.framework" ]]; then
    print -u2 "Sparkle.framework not found in $BIN_DIR"
    exit 1
fi
cp -R "$BIN_DIR/Sparkle.framework" "$FRAMEWORKS_DIR/Sparkle.framework"

# SwiftPM links Sparkle through @rpath. Keep the framework inside the app bundle
# so the packaged app does not depend on the build directory.
RPATHS=$(otool -l "$MACOS_DIR/MaxCLI")
if [[ "$RPATHS" != *"@executable_path/../Frameworks"* ]]; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/MaxCLI"
fi

# SwiftTerm explicitly probes the standard macOS app resource location.
if [[ -d "$BIN_DIR/SwiftTerm_SwiftTerm.bundle" ]]; then
    cp -R "$BIN_DIR/SwiftTerm_SwiftTerm.bundle" "$RESOURCES_DIR/SwiftTerm_SwiftTerm.bundle"
fi

# Localizations are bundled next to the binary by SwiftPM.
if [[ -d "$BIN_DIR/MaxCLI_MaxCLI.bundle" ]]; then
    cp -R "$BIN_DIR/MaxCLI_MaxCLI.bundle" "$RESOURCES_DIR/MaxCLI_MaxCLI.bundle"
fi

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
    codesign --force --deep --sign - "$APP_DIR"
else
    codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_DIR"
fi
print "Built $APP_DIR"
