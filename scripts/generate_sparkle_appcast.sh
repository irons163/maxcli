#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="${OUTPUT_DIR:-dist}"
APP_NAME="${APP_NAME:-MaxCLI}"
RELEASE_TAG="${RELEASE_TAG:-}"
RELEASE_NAME="${RELEASE_NAME:-}"
RELEASE_NOTES="${RELEASE_NOTES:-}"
BUILD_VERSION="${BUILD_VERSION:-}"
PUBLISHED_AT="${PUBLISHED_AT:-}"
ARM64_URL="${ARM64_URL:-}"
ARM64_SIZE="${ARM64_SIZE:-0}"
X86_64_URL="${X86_64_URL:-}"
X86_64_SIZE="${X86_64_SIZE:-0}"

if [[ -z "$RELEASE_TAG" ]]; then
    echo "RELEASE_TAG is required." >&2
    exit 1
fi
if [[ -z "$ARM64_URL" || -z "$X86_64_URL" ]]; then
    echo "ARM64_URL and X86_64_URL are required." >&2
    exit 1
fi

SHORT_VERSION="${RELEASE_TAG#v}"
SHORT_VERSION="${SHORT_VERSION#V}"
if [[ -z "$BUILD_VERSION" ]]; then
    BUILD_VERSION="$(tr -cd '0-9' <<<"$SHORT_VERSION")"
    [[ -n "$BUILD_VERSION" ]] || BUILD_VERSION="1"
fi
if [[ -z "$RELEASE_NAME" ]]; then
    RELEASE_NAME="Release $SHORT_VERSION"
fi

sanitize_release_notes() {
    local raw="$1"
    printf '%s' "$raw" \
        | tr -d '\r' \
        | sed -E 's/\[([^][]+)\]\([^()]*\)/\1/g' \
        | sed -E 's/^#{1,6}[[:space:]]*//g' \
        | sed -E 's/`([^`]*)`/\1/g' \
        | sed -E 's/[*_~]{1,3}//g' \
        | sed -E 's/^[[:space:]]*[-*][[:space:]]+/- /g' \
        | sed -E 's/[[:space:]]+$//g' \
        | awk '
            BEGIN { blank = 0 }
            {
                if ($0 ~ /^[[:space:]]*$/) {
                    if (blank == 0) { print ""; blank = 1 }
                } else {
                    print $0; blank = 0
                }
            }'
}

xml_escape() {
    local value="$1"
    value="${value//&/&amp;}"
    value="${value//</&lt;}"
    value="${value//>/&gt;}"
    value="${value//\"/&quot;}"
    printf '%s' "$value"
}

if [[ -n "$PUBLISHED_AT" && "$PUBLISHED_AT" != "null" ]]; then
    if PUB_DATE="$(date -u -d "$PUBLISHED_AT" '+%a, %d %b %Y %H:%M:%S +0000' 2>/dev/null)"; then
        :
    elif PUB_DATE="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$PUBLISHED_AT" '+%a, %d %b %Y %H:%M:%S +0000' 2>/dev/null)"; then
        :
    else
        PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
    fi
else
    PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
fi

mkdir -p "$OUTPUT_DIR"
RELEASE_NAME_XML="$(xml_escape "$RELEASE_NAME")"
RELEASE_NOTES_SANITIZED="$(sanitize_release_notes "$RELEASE_NOTES")"
[[ -n "${RELEASE_NOTES_SANITIZED//[[:space:]]/}" ]] || RELEASE_NOTES_SANITIZED="Bug fixes and improvements."

generate_feed() {
    local architecture="$1"
    local url="$2"
    local size="$3"
    local output_path="$4"

    cat > "$output_path" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>${APP_NAME} Updates (${architecture})</title>
    <link>https://github.com/irons163/maxcli/releases</link>
    <description>Latest ${APP_NAME} updates for ${architecture}</description>
    <language>en</language>
    <item>
      <title>${RELEASE_NAME_XML}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <description sparkle:format="plain-text"><![CDATA[${RELEASE_NOTES_SANITIZED}]]></description>
      <enclosure
        url="${url}"
        sparkle:version="${BUILD_VERSION}"
        sparkle:shortVersionString="${SHORT_VERSION}"
        type="application/x-apple-diskimage"
        length="${size}" />
    </item>
  </channel>
</rss>
EOF
}

generate_feed "arm64" "$ARM64_URL" "$ARM64_SIZE" "$OUTPUT_DIR/appcast-arm64.xml"
generate_feed "x86_64" "$X86_64_URL" "$X86_64_SIZE" "$OUTPUT_DIR/appcast-x86_64.xml"

echo "Generated Sparkle appcasts in $OUTPUT_DIR"
