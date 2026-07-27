#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
export SWIFT_EXEC="$ROOT/scripts/swiftc-manifest-wrapper.sh"
DEVELOPER_FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
if [[ -d "$DEVELOPER_FRAMEWORKS/Testing.framework" ]]; then
  export DYLD_FRAMEWORK_PATH="$DEVELOPER_FRAMEWORKS${DYLD_FRAMEWORK_PATH:+:$DYLD_FRAMEWORK_PATH}"
  if [[ "${1:-}" == "test" ]]; then
    TEST_BUILD_DIR="$ROOT/.build/$(uname -m)-apple-macosx/debug"
    mkdir -p "$TEST_BUILD_DIR"
    ln -sfn "$DEVELOPER_FRAMEWORKS/Testing.framework" \
      "$TEST_BUILD_DIR/Testing.framework"
    ln -sfn \
      "/Library/Developer/CommandLineTools/Library/Developer/usr/lib/lib_TestingInterop.dylib" \
      "$TEST_BUILD_DIR/lib_TestingInterop.dylib"
  fi
fi
exec xcrun swift "$@"
