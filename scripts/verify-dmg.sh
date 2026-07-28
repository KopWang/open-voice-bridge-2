#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT_DIR="$ROOT/dist"
DISPLAY_NAME="遥控快捷桥"
VERSION="$(
  plutil -extract CFBundleShortVersionString raw -o - \
    "$ROOT/Resources/Info.plist"
)"
BUILD="$(
  plutil -extract CFBundleVersion raw -o - \
    "$ROOT/Resources/Info.plist"
)"
RELEASE_TAG="$VERSION-test.$BUILD"
DMG="${1:-$OUTPUT_DIR/$DISPLAY_NAME-$RELEASE_TAG-macos.dmg}"
CHECKSUM="$DMG.sha256"
SOURCE_ROOT="remote-shortcut-bridge-$RELEASE_TAG-source"
SOURCE_ARCHIVE="$DISPLAY_NAME-$RELEASE_TAG-source.zip"
VERIFY_ROOT="$(mktemp -d /private/tmp/rsb-dmg-verify.XXXXXX)"
MOUNT_POINT="$VERIFY_ROOT/mount"
SOURCE_EXTRACT="$VERIFY_ROOT/source"
ZIP_LIST="$VERIFY_ROOT/zip-entries.txt"
ATTACHED=0

mkdir -p "$MOUNT_POINT" "$SOURCE_EXTRACT"

cleanup() {
  if [[ "$ATTACHED" -eq 1 ]]; then
    hdiutil detach "$MOUNT_POINT" -quiet || true
  fi
  case "$VERIFY_ROOT" in
    /private/tmp/rsb-dmg-verify.*) rm -rf -- "$VERIFY_ROOT" ;;
    *) print -u2 "refusing to clean unexpected path: $VERIFY_ROOT" ;;
  esac
}
trap cleanup EXIT

test -f "$DMG"
test -f "$CHECKSUM"
(
  cd "${DMG:h}"
  shasum -a 256 -c "${CHECKSUM:t}"
)
hdiutil verify "$DMG"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_POINT" "$DMG" -quiet
ATTACHED=1

APP="$MOUNT_POINT/$DISPLAY_NAME.app"
GUIDE="$MOUNT_POINT/首次安装说明.txt"
SOURCE_ZIP="$MOUNT_POINT/$SOURCE_ARCHIVE"

test -L "$MOUNT_POINT/Applications"
test "$(readlink "$MOUNT_POINT/Applications")" = "/Applications"
test -f "$GUIDE"
test -f "$SOURCE_ZIP"
"$ROOT/scripts/verify-app.sh" --universal "$APP"

test "$(
  plutil -extract CFBundleShortVersionString raw -o - \
    "$APP/Contents/Info.plist"
)" = "$VERSION"
test "$(
  plutil -extract CFBundleVersion raw -o - \
    "$APP/Contents/Info.plist"
)" = "$BUILD"

test "$(
  sips -g pixelWidth \
    "$APP/Contents/Resources/RC003-remote-photo.png" |
    tail -n 1 |
    tr -cd '0-9'
)" = "508"
test "$(
  sips -g pixelHeight \
    "$APP/Contents/Resources/RC003-remote-photo.png" |
    tail -n 1 |
    tr -cd '0-9'
)" = "1030"

unzip -Z1 "$SOURCE_ZIP" > "$ZIP_LIST"
for required in \
  "$SOURCE_ROOT/Package.swift" \
  "$SOURCE_ROOT/Sources/XiaomiRemoteBridgeMac/ShortcutBridgeAppModel.swift" \
  "$SOURCE_ROOT/Sources/XiaomiRemoteBridgeMac/ShortcutHIDMonitor.swift" \
  "$SOURCE_ROOT/Sources/XiaomiRemoteBridgeMac/ShortcutSettingsView.swift" \
  "$SOURCE_ROOT/Tests/SelfTest/main.swift" \
  "$SOURCE_ROOT/scripts/build-dmg.sh" \
  "$SOURCE_ROOT/Resources/RC003-remote-photo.png" \
  "$SOURCE_ROOT/device-profiles/xiaomi-rc003.json" \
  "$SOURCE_ROOT/specs/device-profile.schema.json" \
  "$SOURCE_ROOT/docs/LOCAL_RELEASE.md" \
  "$SOURCE_ROOT/LICENSE"; do
  rg -qx "$required" "$ZIP_LIST"
done

if rg -q \
  '(^|/)(\.build|dist|logs?|\.DS_Store)(/|$)|(^|/)__MACOSX(/|$)' \
  "$ZIP_LIST"; then
  print -u2 "source archive contains build, log, or metadata output"
  exit 1
fi

unzip -qq "$SOURCE_ZIP" -d "$SOURCE_EXTRACT"
if rg -a -q \
  '/Users/[^/[:space:]]+|/tmp/remote-bridge|AA:BB:CC:DD:EE:FF' \
  "$SOURCE_EXTRACT/$SOURCE_ROOT/Sources" \
  "$SOURCE_EXTRACT/$SOURCE_ROOT/Tests" \
  "$SOURCE_EXTRACT/$SOURCE_ROOT/Resources" \
  "$SOURCE_EXTRACT/$SOURCE_ROOT/device-profiles" \
  "$SOURCE_EXTRACT/$SOURCE_ROOT/specs" \
  "$SOURCE_EXTRACT/$SOURCE_ROOT/docs" \
  "$SOURCE_EXTRACT/$SOURCE_ROOT/Package.swift" \
  "$SOURCE_EXTRACT/$SOURCE_ROOT/README.md" \
  "$SOURCE_EXTRACT/$SOURCE_ROOT/LICENSE" \
  "$SOURCE_EXTRACT/$SOURCE_ROOT/COPYRIGHT" \
  "$SOURCE_EXTRACT/$SOURCE_ROOT/THIRD_PARTY_NOTICES.md"; then
  print -u2 "source archive contains a forbidden local path or example address"
  exit 1
fi

if rg -a -q 'BlackHole|小米遥控器桥接|Open Voice Bridge' \
  "$GUIDE"; then
  print -u2 "install guide contains a retired product or audio path"
  exit 1
fi

print "DMG VERIFY PASS: $DMG"
print "VERSION: $VERSION ($BUILD), release $RELEASE_TAG"

SIGNATURE_DETAILS="$(codesign -dv --verbose=4 "$APP" 2>&1)"
if rg -q '^Signature=adhoc$' <<<"$SIGNATURE_DETAILS"; then
  print "SIGNATURE: ad-hoc, not notarized"
else
  SIGNING_AUTHORITY="$(
    print -r -- "$SIGNATURE_DETAILS" |
      sed -n 's/^Authority=//p' |
      head -n 1
  )"
  print "SIGNATURE: named (${SIGNING_AUTHORITY:-unknown}), not notarized"
fi
