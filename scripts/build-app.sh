#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="XiaomiRemoteBridgeMac"
DISPLAY_NAME="遥控快捷桥"
OUTPUT_DIR="$ROOT/dist"
APP_DIR="$OUTPUT_DIR/$DISPLAY_NAME.app"
LOCAL_SIGNING_IDENTITY="${RSB_CODESIGN_IDENTITY:-Remote Shortcut Bridge Local Code Signing}"

UNIVERSAL=0
for argument in "$@"; do
  case "$argument" in
    --universal) UNIVERSAL=1 ;;
    *) print -u2 "unknown argument: $argument"; exit 1 ;;
  esac
done

cd "$ROOT"

if [[ "$UNIVERSAL" -eq 1 ]]; then
  "$ROOT/scripts/swift-package.sh" build \
    -c "$CONFIGURATION" \
    --triple arm64-apple-macosx11.0
  ARM64_BIN_DIR="$(
    "$ROOT/scripts/swift-package.sh" build \
      -c "$CONFIGURATION" \
      --triple arm64-apple-macosx11.0 \
      --show-bin-path
  )"

  "$ROOT/scripts/swift-package.sh" build \
    -c "$CONFIGURATION" \
    --triple x86_64-apple-macosx11.0
  X86_64_BIN_DIR="$(
    "$ROOT/scripts/swift-package.sh" build \
      -c "$CONFIGURATION" \
      --triple x86_64-apple-macosx11.0 \
      --show-bin-path
  )"

  UNIVERSAL_BIN="$ROOT/.build/universal-$CONFIGURATION/$APP_NAME"
  mkdir -p "${UNIVERSAL_BIN:h}"
  lipo -create -output "$UNIVERSAL_BIN" \
    "$ARM64_BIN_DIR/$APP_NAME" \
    "$X86_64_BIN_DIR/$APP_NAME"
  BIN_PATH="$UNIVERSAL_BIN"
else
  "$ROOT/scripts/swift-package.sh" build -c "$CONFIGURATION"
  BIN_PATH="$(
    "$ROOT/scripts/swift-package.sh" build \
      -c "$CONFIGURATION" \
      --show-bin-path
  )/$APP_NAME"
fi

case "$APP_DIR" in
  "$ROOT/dist/"*.app) ;;
  *) print -u2 "refusing to clean unexpected app path: $APP_DIR"; exit 1 ;;
esac

rm -rf -- "$APP_DIR"
mkdir -p \
  "$APP_DIR/Contents/MacOS" \
  "$APP_DIR/Contents/Resources/device-profiles"

ditto --norsrc --noextattr --noqtn --noacl \
  "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
strip -S -x "$APP_DIR/Contents/MacOS/$APP_NAME"
for swift_compatibility in swift-5.5 swift-6.2; do
  LOCAL_RPATH="$ROOT/lib/$swift_compatibility/macosx"
  if otool -l "$APP_DIR/Contents/MacOS/$APP_NAME" |
    rg -Fq "path $LOCAL_RPATH "; then
    install_name_tool \
      -delete_rpath "$LOCAL_RPATH" \
      "$APP_DIR/Contents/MacOS/$APP_NAME"
  fi
done

for resource in \
  Info.plist \
  RC003-remote-photo.png \
  OpenVoiceBridge.icns; do
  destination="$APP_DIR/Contents/Resources/$resource"
  if [[ "$resource" == "Info.plist" ]]; then
    destination="$APP_DIR/Contents/Info.plist"
  fi
  ditto --norsrc --noextattr --noqtn --noacl \
    "$ROOT/Resources/$resource" "$destination"
done

for document in LICENSE README.md THIRD_PARTY_NOTICES.md COPYRIGHT; do
  ditto --norsrc --noextattr --noqtn --noacl \
    "$ROOT/$document" "$APP_DIR/Contents/Resources/$document"
done

ditto --norsrc --noextattr --noqtn --noacl \
  "$ROOT/Resources/xiaomi-rc003-shortcut.json" \
  "$APP_DIR/Contents/Resources/device-profiles/xiaomi-rc003.json"

AVAILABLE_IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null)"
if rg -Fq "\"$LOCAL_SIGNING_IDENTITY\"" <<<"$AVAILABLE_IDENTITIES"; then
  print "codesign identity: $LOCAL_SIGNING_IDENTITY"
  codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp=none \
    --sign "$LOCAL_SIGNING_IDENTITY" \
    "$APP_DIR"
elif [[ "${RSB_REQUIRE_LOCAL_SIGNING:-0}" == "1" ]]; then
  print -u2 "required codesign identity is missing: $LOCAL_SIGNING_IDENTITY"
  exit 1
else
  print "codesign identity: ad-hoc fallback"
  codesign \
    --force \
    --deep \
    --timestamp=none \
    --sign - \
    "$APP_DIR"
fi

codesign --verify --deep --strict "$APP_DIR"
print "$APP_DIR"
