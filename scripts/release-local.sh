#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$REPO_ROOT/release/release.env"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

APP_NAME="${APP_NAME:-HerdWatch}"
SCHEME="${SCHEME:-HerdWatch}"
CONFIGURATION="${CONFIGURATION:-Release}"
EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-$REPO_ROOT/release/ExportOptions.plist}"
MINIMUM_SYSTEM_VERSION="${MINIMUM_SYSTEM_VERSION:-26.0}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"
ALLOW_OVERWRITE="${ALLOW_OVERWRITE:-0}"
PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-}"
DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
SPARKLE_SIGN_UPDATE="${SPARKLE_SIGN_UPDATE:-}"
RELEASE_NOTES_URL="${RELEASE_NOTES_URL:-}"

log() { printf '\n==> %s\n' "$*"; }
warn() { printf '\nwarning: %s\n' "$*" >&2; }
die() { printf '\nerror: %s\n' "$*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }

xml_escape() {
  printf '%s' "$1" \
    | sed -e 's/&/\&amp;/g' \
          -e 's/</\&lt;/g' \
          -e 's/>/\&gt;/g' \
          -e 's/"/\&quot;/g'
}

get_build_setting() {
  local key="$1"
  xcodebuild -scheme "$SCHEME" -configuration "$CONFIGURATION" -showBuildSettings \
    | awk -F'= ' -v key="$key" '$1 ~ key" *$" { print $2; exit }'
}

cd "$REPO_ROOT"

require_cmd xcodebuild
require_cmd xcrun
require_cmd hdiutil
require_cmd ditto
require_cmd codesign
require_cmd spctl
require_cmd awk
require_cmd sed

if command -v xcodegen >/dev/null 2>&1; then
  log "Regenerating Xcode project"
  xcodegen generate
else
  warn "xcodegen not found; using existing HerdWatch.xcodeproj"
fi

VERSION="${VERSION:-$(get_build_setting MARKETING_VERSION)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(get_build_setting CURRENT_PROJECT_VERSION)}"
[[ -n "$VERSION" ]] || die "MARKETING_VERSION could not be resolved"
[[ -n "$BUILD_NUMBER" ]] || die "CURRENT_PROJECT_VERSION could not be resolved"

[[ -n "$PUBLIC_BASE_URL" ]] || die "PUBLIC_BASE_URL is required. Copy release/release.env.example to release/release.env and fill it."
PUBLIC_BASE_URL="${PUBLIC_BASE_URL%/}"
[[ -n "$DEVELOPER_ID_APPLICATION" ]] || die "DEVELOPER_ID_APPLICATION is required"
[[ "$DEVELOPER_ID_APPLICATION" != *"Your Name"* ]] || die "DEVELOPER_ID_APPLICATION still contains the example value"

if [[ "$SKIP_NOTARIZE" != "1" ]]; then
  [[ -n "$NOTARY_PROFILE" ]] || die "NOTARY_PROFILE is required unless SKIP_NOTARIZE=1"
fi

RUN_ID="$(date -u +%Y%m%d%H%M%S)"
BUILD_ROOT="$REPO_ROOT/build/release/$VERSION-$RUN_ID"
ARCHIVE_PATH="$BUILD_ROOT/$APP_NAME.xcarchive"
EXPORT_PATH="$BUILD_ROOT/export"
APP_PATH="$EXPORT_PATH/$APP_NAME.app"
RELEASE_DIR="$REPO_ROOT/dist/releases/$VERSION"
DMG_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.dmg"
ZIP_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.zip"
DSYM_ZIP_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.dSYM.zip"
APPCAST_PATH="$REPO_ROOT/dist/appcast.xml"
NOTARY_APP_ZIP="$BUILD_ROOT/$APP_NAME-$VERSION-notary.zip"

if [[ -e "$RELEASE_DIR" && "$ALLOW_OVERWRITE" != "1" ]]; then
  die "$RELEASE_DIR already exists. Set ALLOW_OVERWRITE=1 to reuse it."
fi

mkdir -p "$BUILD_ROOT" "$RELEASE_DIR" "$(dirname "$APPCAST_PATH")"

log "Archiving $APP_NAME $VERSION ($BUILD_NUMBER)"
archive_args=(
  xcodebuild archive
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "generic/platform=macOS"
  -archivePath "$ARCHIVE_PATH"
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION"
  CODE_SIGN_STYLE=Manual
  ENABLE_HARDENED_RUNTIME=YES
)
if [[ -n "$DEVELOPMENT_TEAM" && "$DEVELOPMENT_TEAM" != "TEAMID" ]]; then
  archive_args+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")
fi
"${archive_args[@]}"

log "Exporting Developer ID app"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

[[ -d "$APP_PATH" ]] || die "exported app not found: $APP_PATH"

log "Verifying code signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

if [[ "$SKIP_NOTARIZE" != "1" ]]; then
  log "Notarizing app payload"
  ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$NOTARY_APP_ZIP"
  xcrun notarytool submit "$NOTARY_APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_PATH"
  spctl -a -vvv -t exec "$APP_PATH"
else
  warn "Skipping app notarization because SKIP_NOTARIZE=1"
fi

log "Creating Sparkle update zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

DSYM_PATH="$ARCHIVE_PATH/dSYMs/$APP_NAME.app.dSYM"
if [[ -d "$DSYM_PATH" ]]; then
  log "Creating dSYM archive"
  ditto -c -k --sequesterRsrc --keepParent "$DSYM_PATH" "$DSYM_ZIP_PATH"
else
  warn "dSYM not found: $DSYM_PATH"
fi

log "Creating DMG"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$APP_PATH" \
  -format UDZO \
  "$DMG_PATH"

if [[ "$SKIP_NOTARIZE" != "1" ]]; then
  log "Notarizing DMG"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  spctl -a -vvv -t open "$DMG_PATH"
else
  warn "Skipping DMG notarization because SKIP_NOTARIZE=1"
fi

ZIP_LENGTH="$(stat -f%z "$ZIP_PATH")"
ED_SIGNATURE="REPLACE_WITH_SPARKLE_ED_SIGNATURE"

if [[ -z "$SPARKLE_SIGN_UPDATE" ]] && command -v sign_update >/dev/null 2>&1; then
  SPARKLE_SIGN_UPDATE="$(command -v sign_update)"
fi

if [[ -n "$SPARKLE_SIGN_UPDATE" ]]; then
  [[ -x "$SPARKLE_SIGN_UPDATE" ]] || die "SPARKLE_SIGN_UPDATE is not executable: $SPARKLE_SIGN_UPDATE"
  log "Signing Sparkle update"
  SIGN_OUTPUT="$($SPARKLE_SIGN_UPDATE "$ZIP_PATH")"
  ED_SIGNATURE="$(printf '%s\n' "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
  [[ -n "$ED_SIGNATURE" ]] || die "could not parse sparkle:edSignature from sign_update output: $SIGN_OUTPUT"
else
  warn "SPARKLE_SIGN_UPDATE is not set; appcast.xml will contain a placeholder signature"
fi

PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S %z')"
APPCAST_URL="$PUBLIC_BASE_URL/appcast.xml"
UPDATE_URL="$PUBLIC_BASE_URL/releases/$VERSION/$APP_NAME-$VERSION.zip"
RELEASE_NOTES_XML=""
if [[ -n "$RELEASE_NOTES_URL" ]]; then
  RELEASE_NOTES_XML="    <sparkle:releaseNotesLink>$(xml_escape "$RELEASE_NOTES_URL")</sparkle:releaseNotesLink>"
fi

log "Writing appcast"
cat > "$APPCAST_PATH" <<XML
<?xml version="1.0" standalone="yes"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>$APP_NAME Changelog</title>
    <link>$(xml_escape "$APPCAST_URL")</link>
    <description>Most recent $APP_NAME releases.</description>
    <language>en</language>
    <item>
      <title>Version $(xml_escape "$VERSION")</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:minimumSystemVersion>$(xml_escape "$MINIMUM_SYSTEM_VERSION")</sparkle:minimumSystemVersion>
$RELEASE_NOTES_XML
      <enclosure
        url="$(xml_escape "$UPDATE_URL")"
        sparkle:version="$(xml_escape "$BUILD_NUMBER")"
        sparkle:shortVersionString="$(xml_escape "$VERSION")"
        length="$ZIP_LENGTH"
        type="application/octet-stream"
        sparkle:edSignature="$(xml_escape "$ED_SIGNATURE")" />
    </item>
  </channel>
</rss>
XML

cat <<EOF

Release files:
  $DMG_PATH
  $ZIP_PATH
  $APPCAST_PATH

Upload these paths to R2 so that URLs resolve as:
  $PUBLIC_BASE_URL/appcast.xml
  $PUBLIC_BASE_URL/releases/$VERSION/$APP_NAME-$VERSION.dmg
  $PUBLIC_BASE_URL/releases/$VERSION/$APP_NAME-$VERSION.zip

LP download URL:
  $PUBLIC_BASE_URL/releases/$VERSION/$APP_NAME-$VERSION.dmg

Sparkle appcast URL:
  $PUBLIC_BASE_URL/appcast.xml
EOF
