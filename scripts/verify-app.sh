#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
UNIVERSAL=0
APP=""

for argument in "$@"; do
  case "$argument" in
    --universal) UNIVERSAL=1 ;;
    *) APP="$argument" ;;
  esac
done

APP="${APP:-$ROOT/dist/遥控快捷桥.app}"
PLIST="$APP/Contents/Info.plist"
BINARY="$APP/Contents/MacOS/XiaomiRemoteBridgeMac"

test -d "$APP"
test -f "$PLIST"
test -x "$BINARY"

for resource in \
  LICENSE \
  README.md \
  THIRD_PARTY_NOTICES.md \
  COPYRIGHT \
  RC003-remote-photo.png \
  OpenVoiceBridge.icns \
  device-profiles/xiaomi-rc003.json; do
  test -f "$APP/Contents/Resources/$resource"
done

test ! -e "$APP/Contents/Resources/ARN9-remote-photo.png"
test ! -e "$APP/Contents/Resources/device-profiles/xiaomi-arn9.json"
test ! -e "$APP/Contents/Resources/device-profiles/dji-mic-2.json"

cmp -s \
  "$ROOT/Resources/xiaomi-rc003-shortcut.json" \
  "$APP/Contents/Resources/device-profiles/xiaomi-rc003.json"

test "$(plutil -extract CFBundleDisplayName raw -o - "$PLIST")" = "遥控快捷桥"
test "$(plutil -extract CFBundleName raw -o - "$PLIST")" = "RemoteShortcutBridge"
test "$(plutil -extract CFBundleIdentifier raw -o - "$PLIST")" = \
  "com.kopwang.RemoteShortcutBridge"
test "$(plutil -extract CFBundleExecutable raw -o - "$PLIST")" = \
  "XiaomiRemoteBridgeMac"
test "$(plutil -extract CFBundleIconFile raw -o - "$PLIST")" = \
  "OpenVoiceBridge.icns"
test "$(plutil -extract LSMinimumSystemVersion raw -o - "$PLIST")" = "11.0"

for forbidden_key in \
  NSMicrophoneUsageDescription \
  NSBluetoothAlwaysUsageDescription \
  NSBluetoothPeripheralUsageDescription; do
  if plutil -extract "$forbidden_key" raw -o - "$PLIST" >/dev/null 2>&1; then
    print -u2 "forbidden privacy declaration: $forbidden_key"
    exit 1
  fi
done

codesign --verify --deep --strict "$APP"
file "$BINARY" | rg -q 'Mach-O 64-bit executable'

ARCHS="$(lipo -archs "$BINARY")"
if [[ "$UNIVERSAL" -eq 1 ]]; then
  for required in arm64 x86_64; do
    if ! print -r -- "$ARCHS" | tr ' ' '\n' | rg -qx "$required"; then
      print -u2 "missing architecture in universal binary: $required"
      exit 1
    fi
  done
else
  print -r -- "$ARCHS" | tr ' ' '\n' | rg -qx "$(uname -m)"
fi
print "architectures: $ARCHS"

EXPECTED_FILES=$'Contents/Info.plist\nContents/MacOS/XiaomiRemoteBridgeMac\nContents/Resources/COPYRIGHT\nContents/Resources/LICENSE\nContents/Resources/OpenVoiceBridge.icns\nContents/Resources/RC003-remote-photo.png\nContents/Resources/README.md\nContents/Resources/THIRD_PARTY_NOTICES.md\nContents/Resources/device-profiles/xiaomi-rc003.json\nContents/_CodeSignature/CodeResources'
ACTUAL_FILES="$(
  find "$APP/Contents" -type f |
    sed "s#^$APP/##" |
    LC_ALL=C sort
)"
test "$ACTUAL_FILES" = "$EXPECTED_FILES"

if rg -a -q \
  '/Users/[^/[:space:]]+|/tmp/remote-bridge|AA:BB:CC:DD:EE:FF' \
  "$APP/Contents"; then
  print -u2 "bundle contains a forbidden local path or example address"
  exit 1
fi

if rg -a -q '小米遥控器桥接|Open Voice Bridge|BlackHole' \
  "$APP/Contents"; then
  print -u2 "bundle contains a retired user-visible product or audio path"
  exit 1
fi

if otool -L "$BINARY" |
  rg -q 'CoreBluetooth|AVFoundation|AVFAudio|CoreAudio|AudioToolbox'; then
  print -u2 "controller-only executable links an audio or Bluetooth framework"
  exit 1
fi

SIGNATURE_DETAILS="$(codesign -dv --verbose=4 "$APP" 2>&1)"
if [[ "${RSB_REQUIRE_LOCAL_SIGNING:-0}" == "1" ]]; then
  rg -Fq 'Authority=Remote Shortcut Bridge Local Code Signing' \
    <<<"$SIGNATURE_DETAILS"
elif ! rg -q '^Signature=adhoc$|^Authority=' <<<"$SIGNATURE_DETAILS"; then
  print -u2 "app has no recognized code signature"
  exit 1
fi

print "APP VERIFY PASS: $APP"
