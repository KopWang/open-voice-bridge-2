#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
export SWIFT_EXEC="$ROOT/scripts/swiftc-manifest-wrapper.sh"
exec xcrun swift "$@"
