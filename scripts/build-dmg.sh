#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT_DIR="$ROOT/dist"
DISPLAY_NAME="遥控快捷桥"
APP_DIR="$OUTPUT_DIR/$DISPLAY_NAME.app"
PLIST="$ROOT/Resources/Info.plist"
VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$PLIST")"
BUILD="$(plutil -extract CFBundleVersion raw -o - "$PLIST")"
RELEASE_TAG="$VERSION-test.$BUILD"
DMG_BASENAME="$DISPLAY_NAME-$RELEASE_TAG-macos.dmg"
DMG="$OUTPUT_DIR/$DMG_BASENAME"
SOURCE_ROOT="remote-shortcut-bridge-$RELEASE_TAG-source"
SOURCE_ARCHIVE="$DISPLAY_NAME-$RELEASE_TAG-source.zip"

mkdir -p "$OUTPUT_DIR"
WORK_DIR="$(mktemp -d "$OUTPUT_DIR/.package-work.XXXXXX")"
STAGING="$WORK_DIR/dmg"
SOURCE_DIR="$WORK_DIR/$SOURCE_ROOT"

cleanup() {
  case "$WORK_DIR" in
    "$OUTPUT_DIR/.package-work."*) rm -rf -- "$WORK_DIR" ;;
    *) print -u2 "refusing to clean unexpected work path: $WORK_DIR" ;;
  esac
}
trap cleanup EXIT

mkdir -p "$STAGING" "$SOURCE_DIR/docs"

"$ROOT/scripts/swift-package.sh" package clean
"$ROOT/scripts/build-app.sh" --universal
"$ROOT/scripts/verify-app.sh" --universal "$APP_DIR"

ditto --norsrc --noextattr --noqtn --noacl \
  "$APP_DIR" "$STAGING/$DISPLAY_NAME.app"
ln -s /Applications "$STAGING/Applications"

for document in \
  Resources/首次安装说明.txt \
  LICENSE \
  COPYRIGHT \
  THIRD_PARTY_NOTICES.md; do
  ditto --norsrc --noextattr --noqtn --noacl \
    "$ROOT/$document" "$STAGING/${document:t}"
done

for item in \
  Package.swift \
  Sources \
  Tests \
  scripts \
  Resources \
  device-profiles \
  specs \
  README.md \
  LICENSE \
  COPYRIGHT \
  THIRD_PARTY_NOTICES.md; do
  ditto --norsrc --noextattr --noqtn --noacl \
    "$ROOT/$item" "$SOURCE_DIR/$item"
done

for item in ARCHITECTURE.md ADDING_A_DEVICE.md LOCAL_RELEASE.md; do
  ditto --norsrc --noextattr --noqtn --noacl \
    "$ROOT/docs/$item" "$SOURCE_DIR/docs/$item"
done

ditto -c -k --keepParent --norsrc --noextattr --noqtn --noacl \
  "$SOURCE_DIR" "$STAGING/$SOURCE_ARCHIVE"

hdiutil create \
  -volname "$DISPLAY_NAME $RELEASE_TAG" \
  -srcfolder "$STAGING" \
  -fs "HFS+" \
  -format UDZO \
  -ov \
  "$DMG"

(
  cd "$OUTPUT_DIR"
  shasum -a 256 "$DMG_BASENAME" > "$DMG_BASENAME.sha256"
)

print "DMG: $DMG"
print "SHA256: $DMG.sha256"
print "VERSION: $VERSION ($BUILD), release $RELEASE_TAG"
