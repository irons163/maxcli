#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$(cd -- "$(dirname -- "$0")/.." && pwd)}"
APP_NAME="MaxCLI"
VERSION="${VERSION:-${APP_VERSION:-}}"
BUILD_VERSION="${BUILD_VERSION:-${APP_BUILD_VERSION:-}}"
BUILD_TRIPLE="${BUILD_TRIPLE:-}"
ARCH_LABEL="${ARCH_LABEL:-${BUILD_TRIPLE%%-*}}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application}"
NOTARIZE="${NOTARIZE:-1}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_DIR/dist}"
WORK_DIR="${WORK_DIR:-$PROJECT_DIR/build/release-${ARCH_LABEL:-native}}"

if [[ -z "$VERSION" ]]; then
    echo "VERSION or APP_VERSION is required." >&2
    exit 1
fi
if [[ -z "$BUILD_VERSION" ]]; then
    echo "BUILD_VERSION or APP_BUILD_VERSION is required." >&2
    exit 1
fi
if [[ -z "$ARCH_LABEL" ]]; then
    echo "ARCH_LABEL or BUILD_TRIPLE is required." >&2
    exit 1
fi

SAFE_VERSION="$(printf '%s' "$VERSION" | sed -E 's/[^A-Za-z0-9._-]+/-/g; s/^-+//; s/-+$//')"
if [[ -z "$SAFE_VERSION" ]]; then
    SAFE_VERSION="0.0.0"
fi

APP_DIR="$PROJECT_DIR/build/MaxCLI.app"
STAGING_DIR="$WORK_DIR/staging"
DMG_NAME="${APP_NAME}-${SAFE_VERSION}-${ARCH_LABEL}.dmg"
DMG_PATH="$WORK_DIR/$DMG_NAME"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$STAGING_DIR" "$OUTPUT_DIR"

echo "==> Building $APP_NAME ($ARCH_LABEL)"
(
    cd "$PROJECT_DIR"
    APP_VERSION="$VERSION" \
    APP_BUILD_VERSION="$BUILD_VERSION" \
    BUILD_TRIPLE="$BUILD_TRIPLE" \
    CODESIGN_IDENTITY="$CODESIGN_IDENTITY" \
    ./scripts/build-app.sh release
)

if [[ ! -d "$APP_DIR" ]]; then
    echo "Expected app bundle was not created: $APP_DIR" >&2
    exit 1
fi

APP_BINARY="$APP_DIR/Contents/MacOS/$APP_NAME"
if [[ ! -f "$APP_BINARY" ]]; then
    echo "Unable to locate app executable: $APP_BINARY" >&2
    exit 1
fi

if [[ -n "$BUILD_TRIPLE" ]]; then
    EXPECTED_ARCH="${BUILD_TRIPLE%%-*}"
    APP_ARCHES="$(lipo -archs "$APP_BINARY")"
    if ! grep -Eq "(^|[[:space:]])${EXPECTED_ARCH}([[:space:]]|$)" <<<"$APP_ARCHES"; then
        echo "App binary architectures ($APP_ARCHES) do not include $EXPECTED_ARCH." >&2
        exit 1
    fi
fi

SPARKLE_FRAMEWORK="$APP_DIR/Contents/Frameworks/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
    echo "Sparkle.framework is missing from the app bundle." >&2
    exit 1
fi

if [[ "$CODESIGN_IDENTITY" != "-" ]]; then
    sign_with_developer_id() {
        local target="$1"
        codesign \
            --force \
            --timestamp \
            --options runtime \
            --preserve-metadata=identifier,entitlements,flags \
            --sign "$CODESIGN_IDENTITY" \
            "$target"
    }

    echo "==> Signing nested Sparkle components"
    while IFS= read -r -d '' nested_binary; do
        sign_with_developer_id "$nested_binary"
    done < <(
        find "$SPARKLE_FRAMEWORK/Versions" -type f \
            \( -perm -111 -o -name "*.dylib" \) \
            -print0
    )

    while IFS= read -r -d '' nested_bundle; do
        sign_with_developer_id "$nested_bundle"
    done < <(
        find "$SPARKLE_FRAMEWORK/Versions" -type d \
            \( -name "*.xpc" -o -name "*.app" \) \
            -print0
    )

    sign_with_developer_id "$SPARKLE_FRAMEWORK"
    sign_with_developer_id "$APP_DIR"
fi

echo "==> Verifying app signature"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "==> Creating DMG"
cp -R "$APP_DIR" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

if [[ "$NOTARIZE" == "1" ]]; then
    echo "==> Notarizing DMG"
    NOTARY_OUTPUT="$(xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)"
    echo "$NOTARY_OUTPUT"
    if ! grep -Eq 'status:[[:space:]]+Accepted' <<<"$NOTARY_OUTPUT"; then
        echo "Notarization failed." >&2
        exit 1
    fi
    xcrun stapler staple "$DMG_PATH"
fi

cp "$DMG_PATH" "$OUTPUT_DIR/$DMG_NAME"
echo "DMG ready: $OUTPUT_DIR/$DMG_NAME"
