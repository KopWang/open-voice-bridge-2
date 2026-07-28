# Local Test Release

This project publishes a locally signed, unnotarized macOS test build. It does
not require an Apple Developer Program account or a Developer ID certificate.

## Release identity

- App: `遥控快捷桥.app`
- Bundle ID: `com.kopwang.RemoteShortcutBridge`
- Version: `0.1.1 (2)`
- Tag: `v0.1.1-test.2`
- Signing name: `Remote Shortcut Bridge Local Code Signing`

## Build

```bash
./scripts/test.sh
./scripts/swift-package.sh test
./scripts/create-local-signing-identity.sh
RSB_REQUIRE_LOCAL_SIGNING=1 ./scripts/build-app.sh --universal
RSB_REQUIRE_LOCAL_SIGNING=1 ./scripts/verify-app.sh --universal
RSB_REQUIRE_LOCAL_SIGNING=1 ./scripts/build-dmg.sh
RSB_REQUIRE_LOCAL_SIGNING=1 ./scripts/verify-dmg.sh
```

The signing helper creates a ten-year self-signed code-signing identity in the
current user's login keychain. It writes certificate material only in a
mode-0700 temporary directory and removes it on exit. It never reads or stores
the user's login password.

## Outputs

```text
dist/遥控快捷桥.app
dist/遥控快捷桥-0.1.1-test.2-macos.dmg
dist/遥控快捷桥-0.1.1-test.2-macos.dmg.sha256
```

The DMG includes the app, installation guide, GPL materials, and the
corresponding source archive.

## GitHub prerelease

Create tag `v0.1.1-test.2`, mark the release as a prerelease, and attach the DMG
and checksum. State plainly that the build is locally signed and not notarized.
Do not describe it as a public trusted macOS distribution.
