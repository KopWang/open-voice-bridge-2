#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
REAL_SWIFTC="/Library/Developer/CommandLineTools/usr/bin/swiftc"
MANIFEST_API="/Library/Developer/CommandLineTools/usr/lib/swift/pm/ManifestAPI"
DEVELOPER_FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"

if [[ ! -x "$REAL_SWIFTC" ]]; then
  REAL_SWIFTC="$(xcrun -f swiftc)"
fi

is_manifest_compile=0
for argument in "$@"; do
  if [[ "$argument" == "-package-description-version" ]]; then
    is_manifest_compile=1
    break
  fi
done

if [[ "$is_manifest_compile" -eq 0 ]]; then
  needs_testing_framework=0
  for argument in "$@"; do
    if [[ "$argument" == *Tests* ]]; then
      needs_testing_framework=1
      break
    fi
  done
  if [[ "$needs_testing_framework" -eq 1 && -d "$DEVELOPER_FRAMEWORKS/Testing.framework" ]]; then
    exec "$REAL_SWIFTC" "$@" \
      -F "$DEVELOPER_FRAMEWORKS" \
      -plugin-path "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
  fi
  exec "$REAL_SWIFTC" "$@"
fi

# Some Command Line Tools updates leave an older private PackageDescription
# interface beside a newer dylib. SwiftPM prefers that private interface, then
# fails to link the manifest. Build a user-writable module view containing only
# the public interfaces that match the installed dylib.
FIXED_API="$ROOT/.build/manifest-api-public"
FIXED_MODULE="$FIXED_API/PackageDescription.swiftmodule"
mkdir -p "$FIXED_MODULE"
for architecture in arm64 x86_64; do
  for extension in swiftinterface swiftdoc; do
    source="$MANIFEST_API/PackageDescription.swiftmodule/$architecture-apple-macos.$extension"
    if [[ -f "$source" ]]; then
      cp -f "$source" "$FIXED_MODULE/"
    fi
  done
done

typeset -a rewritten
replace_next_include=0
for argument in "$@"; do
  if [[ "$replace_next_include" -eq 1 ]]; then
    if [[ "$argument" == "$MANIFEST_API" ]]; then
      rewritten+=("$FIXED_API")
    else
      rewritten+=("$argument")
    fi
    replace_next_include=0
    continue
  fi

  rewritten+=("$argument")
  if [[ "$argument" == "-I" ]]; then
    replace_next_include=1
  fi
done

exec "$REAL_SWIFTC" "${rewritten[@]}"
