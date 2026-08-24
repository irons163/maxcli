#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

OUTPUT_DIR="$TEMP_DIR/dist" \
RELEASE_TAG="v0.1.0" \
RELEASE_NAME="MaxCLI <stable>" \
RELEASE_NOTES=$'## Fixes\n\n- Keeps updates over HTTPS & stable.' \
BUILD_VERSION="1" \
PUBLISHED_AT="2026-08-24T00:00:00Z" \
ARM64_URL="https://github.com/irons163/maxcli/releases/download/v0.1.0/MaxCLI-0.1.0-apple-silicon.dmg" \
ARM64_SIZE="123" \
X86_64_URL="https://github.com/irons163/maxcli/releases/download/v0.1.0/MaxCLI-0.1.0-intel.dmg" \
X86_64_SIZE="456" \
"$SCRIPT_DIR/generate_sparkle_appcast.sh"

for appcast in "$TEMP_DIR/dist/appcast-arm64.xml" "$TEMP_DIR/dist/appcast-x86_64.xml"; do
    [[ -f "$appcast" ]]
    rg -q '<rss version="2.0"' "$appcast"
    rg -q 'sparkle:version="1"' "$appcast"
    rg -q 'sparkle:shortVersionString="0.1.0"' "$appcast"
    rg -q 'https://github.com/irons163/maxcli/releases/download/v0.1.0/' "$appcast"
    rg -q '&lt;stable&gt;' "$appcast"
    if command -v xmllint >/dev/null 2>&1; then
        xmllint --noout "$appcast"
    fi
done

echo "Sparkle appcast generator test passed."
