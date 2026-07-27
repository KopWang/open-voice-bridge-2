# Remote Shortcut Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build, install, and publish a controller-only macOS app that maps every RC003 button to a keyboard shortcut, with the microphone button defaulting to `Control + Option` for Typeless.

**Architecture:** Keep the upstream Swift target and verified RC003 HID identity, report parsing, lifecycle protection, event suppression, launch-at-login support, and packaging checks. Add a separate controller-only settings model, edge-aware shortcut emitter, HID monitor, app model, recorder, and compact SwiftUI surface; make the app entry point construct only these types so BLE, ATVV, CoreAudio, microphone, and F5-to-Fn services are unreachable at runtime.

**Tech Stack:** Swift 5 language mode, Swift Package Manager, SwiftUI/AppKit, IOKit HID, CoreGraphics events, ServiceManagement, Swift Testing, zsh packaging scripts, local macOS code signing, GitHub prerelease.

## Global Constraints

- Display name is `Remote Shortcut Bridge` / `遥控快捷桥`.
- Bundle identifier is `com.kopwang.RemoteShortcutBridge`.
- Initial app version/build is `0.1.0 (1)` and release tag is `v0.1.0-test.1`.
- RC003 is the only supported device in this release.
- The RC003 microphone, BLE GATT, ATVV, CoreAudio routing, local microphone capture, microphone permission, and BlackHole are not runtime dependencies.
- Input Monitoring and Accessibility are the only required privacy permissions.
- Every one of the 13 RC003 buttons supports disabled, an arbitrary recorded keyboard chord, or a verified built-in system action.
- Modifier-only chords are valid; an empty chord is disabled.
- Held synthetic keys are force-released on disconnect, permission loss, mapping replacement, pause, reader-generation change, and termination.
- Keep GPL-3.0 license, attribution, notices, and corresponding source in the DMG.
- Use local signing identity `Remote Shortcut Bridge Local Code Signing`; do not claim Developer ID signing or notarization.
- Do not remove the upstream app or BlackHole until the new app passes real RC003 + Typeless + DJI Mic Mini acceptance.

---

### Task 1: Restore a Reproducible Swift Build and Add Product Contracts

**Files:**
- Modify: `Package.swift`
- Modify: `Resources/Info.plist`
- Create: `Tests/XiaomiRemoteBridgeMacTests/ProductIdentityTests.swift`
- Modify: `scripts/test.sh`

**Interfaces:**
- Consumes: the existing `XiaomiRemoteBridgeMac` executable target.
- Produces: a locally parseable package manifest and bundle metadata for `com.kopwang.RemoteShortcutBridge`.

- [ ] **Step 1: Record the failing manifest and metadata tests**

Create tests that load `Resources/Info.plist` and assert:

```swift
#expect(plist["CFBundleDisplayName"] as? String == "遥控快捷桥")
#expect(plist["CFBundleIdentifier"] as? String == "com.kopwang.RemoteShortcutBridge")
#expect(plist["CFBundleShortVersionString"] as? String == "0.1.0")
#expect(plist["CFBundleVersion"] as? String == "1")
#expect(plist["NSMicrophoneUsageDescription"] == nil)
#expect(plist["NSBluetoothAlwaysUsageDescription"] == nil)
```

Add `xcrun swift package dump-package` to `scripts/test.sh` before compilation.

- [ ] **Step 2: Run the red checks**

Run:

```bash
xcrun swift package dump-package
xcrun swift test --filter ProductIdentityTests
```

Expected: manifest parsing fails on `swiftLanguageModes`, and identity assertions fail against the upstream plist.

- [ ] **Step 3: Apply the minimum compatibility and identity changes**

Use SwiftPM's compatible spelling:

```swift
swiftLanguageVersions: [.v5]
```

Set the plist keys exactly:

```text
CFBundleDisplayName = 遥控快捷桥
CFBundleName = RemoteShortcutBridge
CFBundleIdentifier = com.kopwang.RemoteShortcutBridge
CFBundleShortVersionString = 0.1.0
CFBundleVersion = 1
```

Remove the Bluetooth and microphone usage-description keys. Keep the internal executable name `XiaomiRemoteBridgeMac`.

- [ ] **Step 4: Run the green checks**

Run:

```bash
xcrun swift package dump-package
xcrun swift test --filter ProductIdentityTests
```

Expected: both commands pass.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Resources/Info.plist Tests/XiaomiRemoteBridgeMacTests/ProductIdentityTests.swift scripts/test.sh
git commit -m "build: establish remote shortcut bridge identity"
```

### Task 2: Unify the RC003 Button and Shortcut Value Models

**Files:**
- Modify: `Sources/XiaomiRemoteBridgeMac/RemoteButtons.swift`
- Create: `Sources/XiaomiRemoteBridgeMac/ShortcutBinding.swift`
- Create: `Sources/XiaomiRemoteBridgeMac/ShortcutBridgeSettings.swift`
- Modify: `Tests/XiaomiRemoteBridgeMacTests/RemoteButtonsTests.swift`
- Create: `Tests/XiaomiRemoteBridgeMacTests/ShortcutBindingTests.swift`
- Create: `Tests/XiaomiRemoteBridgeMacTests/ShortcutBridgeSettingsTests.swift`

**Interfaces:**
- Consumes: `RemoteEventEdge`, `ButtonAction`, and the verified RC003 usage table.
- Produces: `RemoteButton.microphone`, `KeyModifier`, `ShortcutKey`, `KeyChord`, `SystemAction`, `ShortcutBinding`, and `ShortcutBridgeSettings`.

- [ ] **Step 1: Add failing button and value-model tests**

Assert that `RemoteButton.allCases.count == 13`, usage `0x003E` maps to `.microphone`, and its native F5 descriptor is key code `96`.

Exercise these signatures:

```swift
let modifiers: Set<KeyModifier> = [.control, .option]
let chord = KeyChord(modifiers: modifiers, key: nil)
#expect(chord != nil)
#expect(chord?.displayName == "Control + Option")
#expect(KeyChord(modifiers: [], key: nil) == nil)
```

Round-trip `.disabled`, `.chord`, and `.system` through `JSONEncoder` and `JSONDecoder`.

- [ ] **Step 2: Run the tests and verify failure**

Run:

```bash
xcrun swift test --filter RemoteButtonsTests
xcrun swift test --filter ShortcutBindingTests
```

Expected: `.microphone` and shortcut types are missing.

- [ ] **Step 3: Implement the value types**

Define:

```swift
enum KeyModifier: String, Codable, CaseIterable, Comparable {
    case control, option, shift, command
}

struct ShortcutKey: Codable, Equatable {
    let keyCode: UInt16
    let displayName: String
}

struct KeyChord: Codable, Equatable {
    let modifiers: Set<KeyModifier>
    let key: ShortcutKey?

    init?(modifiers: Set<KeyModifier>, key: ShortcutKey?)
}

enum SystemAction: String, Codable, Equatable {
    case volumeUp, volumeDown, showDesktop, contextMenu
}

enum ShortcutBinding: Codable, Equatable {
    case disabled
    case chord(KeyChord)
    case system(SystemAction)
}
```

Encode `ShortcutBinding` with explicit `kind`, `chord`, and `system` fields so persistence is stable and inspectable.

- [ ] **Step 4: Implement settings and defaults**

`ShortcutBridgeSettings` owns:

```swift
@Published var bindings: [RemoteButton: ShortcutBinding]
@Published var launchAtLoginEnabled: Bool
func binding(for button: RemoteButton) -> ShortcutBinding
func setBinding(_ binding: ShortcutBinding, for button: RemoteButton)
func resetBindings()
```

Use the new bundle's `UserDefaults`. Defaults are microphone `Control + Option`, navigation keys, `Escape`, `Return`, `Delete`, `Command + Tab`, and the four verified system actions from the design.

- [ ] **Step 5: Run model and persistence tests**

Run:

```bash
xcrun swift test --filter ShortcutBindingTests
xcrun swift test --filter ShortcutBridgeSettingsTests
xcrun swift test --filter RemoteButtonsTests
```

Expected: all pass, including default coverage for all 13 buttons and saved-value reload.

- [ ] **Step 6: Commit**

```bash
git add Sources/XiaomiRemoteBridgeMac/RemoteButtons.swift Sources/XiaomiRemoteBridgeMac/ShortcutBinding.swift Sources/XiaomiRemoteBridgeMac/ShortcutBridgeSettings.swift Tests/XiaomiRemoteBridgeMacTests
git commit -m "feat: model arbitrary RC003 shortcut bindings"
```

### Task 3: Build a Deterministic, Force-Releasing Shortcut Emitter

**Files:**
- Create: `Sources/XiaomiRemoteBridgeMac/ShortcutEmitter.swift`
- Modify: `Sources/XiaomiRemoteBridgeMac/KeyboardInjector.swift`
- Create: `Tests/XiaomiRemoteBridgeMacTests/ShortcutEmitterTests.swift`

**Interfaces:**
- Consumes: `RemoteButton`, `RemoteEventEdge`, and `ShortcutBinding`.
- Produces: `ShortcutEvent`, `ShortcutEventSink`, `CGShortcutEventSink`, and `ShortcutEmitter`.

- [ ] **Step 1: Write failing event-sequence tests**

Use an in-memory sink and assert:

```swift
emitter.handle(.down, button: .microphone, binding: controlOption)
emitter.handle(.up, button: .microphone, binding: controlOption)
#expect(sink.events == [
    .modifier(.control, isDown: true, flags: [.control]),
    .modifier(.option, isDown: true, flags: [.control, .option]),
    .modifier(.option, isDown: false, flags: [.control]),
    .modifier(.control, isDown: false, flags: []),
])
```

Add tests for modifier-plus-key order, duplicate down, stray up, disabled/system bindings, replacing a held mapping, and `forceReleaseAll(reason:)`.

- [ ] **Step 2: Run the red test**

Run:

```bash
xcrun swift test --filter ShortcutEmitterTests
```

Expected: emitter types are missing.

- [ ] **Step 3: Implement the pure state machine**

Define:

```swift
protocol ShortcutEventSink {
    func post(_ event: ShortcutEvent) -> Bool
}

final class ShortcutEmitter {
    func handle(_ edge: RemoteEventEdge, button: RemoteButton, binding: ShortcutBinding) -> Bool
    func replaceBinding(for button: RemoteButton) -> Bool
    func forceReleaseAll(reason: String) -> Bool
}
```

Store the exact chord held per button. Sort modifiers `Control`, `Option`, `Shift`, `Command`; release in reverse. System actions fire once on down and hold no state.

- [ ] **Step 4: Implement the CoreGraphics sink**

`CGShortcutEventSink` creates HID-system-state `CGEvent`s, applies accumulated flags, sets `KeyboardInjector.syntheticEventMarker`, and posts at `.cghidEventTap`. It maps modifier virtual key codes to Control `59`, Option `58`, Shift `56`, and Command `55`. System actions reuse the existing verified injector behavior.

- [ ] **Step 5: Run the green tests**

Run:

```bash
xcrun swift test --filter ShortcutEmitterTests
```

Expected: every ordering and cleanup test passes.

- [ ] **Step 6: Commit**

```bash
git add Sources/XiaomiRemoteBridgeMac/ShortcutEmitter.swift Sources/XiaomiRemoteBridgeMac/KeyboardInjector.swift Tests/XiaomiRemoteBridgeMacTests/ShortcutEmitterTests.swift
git commit -m "feat: emit edge-aware keyboard shortcuts"
```

### Task 4: Add a Modifier-Only-Capable Shortcut Recorder

**Files:**
- Create: `Sources/XiaomiRemoteBridgeMac/ShortcutRecorder.swift`
- Create: `Tests/XiaomiRemoteBridgeMacTests/ShortcutRecorderTests.swift`

**Interfaces:**
- Consumes: normalized modifier flags, key code, key label, and whether the event is synthetic.
- Produces: `ShortcutRecorder.State`, `handleFlagsChanged`, `handleKeyDown`, `handleKeyUp`, `cancel`, and `onComplete`.

- [ ] **Step 1: Write failing recorder tests**

Cover:

```swift
recorder.handleFlagsChanged([.control, .option])
recorder.handleFlagsChanged([])
#expect(completed == KeyChord(modifiers: [.control, .option], key: nil))
```

Also cover `Command + Shift + K`, Escape cancellation, synthetic-event rejection, empty modifier transitions, and one-primary-key-only behavior.

- [ ] **Step 2: Verify the tests fail**

Run:

```bash
xcrun swift test --filter ShortcutRecorderTests
```

Expected: recorder type is missing.

- [ ] **Step 3: Implement the pure recorder**

The recorder snapshots the largest non-empty modifier set during a recording and completes when all held keys/modifiers are released. A primary key completes only after its key-up and all modifiers are up. Escape calls `onCancel` and never mutates the existing binding.

- [ ] **Step 4: Run the recorder tests**

Run:

```bash
xcrun swift test --filter ShortcutRecorderTests
```

Expected: all recorder tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/XiaomiRemoteBridgeMac/ShortcutRecorder.swift Tests/XiaomiRemoteBridgeMacTests/ShortcutRecorderTests.swift
git commit -m "feat: record modifier-only shortcuts"
```

### Task 5: Add the Controller-Only HID Runtime

**Files:**
- Create: `Sources/XiaomiRemoteBridgeMac/ShortcutHIDMonitor.swift`
- Create: `Sources/XiaomiRemoteBridgeMac/ShortcutBridgeRuntime.swift`
- Create: `Tests/XiaomiRemoteBridgeMacTests/ShortcutHIDRuntimeTests.swift`
- Modify: `Sources/XiaomiRemoteBridgeMac/KeyboardEventSuppressor.swift`

**Interfaces:**
- Consumes: exact RC003 VID `0x2717`, PID `0x32B8`, report ID `1`, `RemoteHIDReportParser`, `RemoteDeviceLifecycle`, `ShortcutBridgeSettings`, and `ShortcutEmitter`.
- Produces: `ShortcutHIDMonitor.start()`, `stop()`, `refresh()`, status/connection callbacks, and `ShortcutBridgeRuntime.start()` / `stop()`.

- [ ] **Step 1: Write failing report-edge and lifecycle tests**

Extract a pure edge tracker:

```swift
let transitions = tracker.update(usages: [0x003E])
#expect(transitions == [.init(button: .microphone, edge: .down)])
#expect(tracker.update(usages: []) == [.init(button: .microphone, edge: .up)])
```

Test one generation's late report is rejected after removal, all held shortcuts are force-released on removal and permission loss, and all 13 usages traverse the same path.

- [ ] **Step 2: Run the red HID runtime tests**

Run:

```bash
xcrun swift test --filter ShortcutHIDRuntimeTests
```

Expected: controller-only monitor and tracker are missing.

- [ ] **Step 3: Implement the monitor**

Reuse the upstream manager scheduling, generation tagging, exclusive-first open, monitored fallback, correlated native-event suppression, and one-second permission monitor. Replace `ButtonAction` and the separate voice callback with:

```swift
for transition in tracker.update(usages: usages) {
    eventSuppressor.arm(button: transition.button, edge: transition.edge)
    emitter.handle(
        transition.edge,
        button: transition.button,
        binding: settings.binding(for: transition.button)
    )
}
```

On stop, removal, unreadable device, permission loss, and refresh, call `emitter.forceReleaseAll(reason:)` before clearing state.

- [ ] **Step 4: Add the runtime construction boundary**

`ShortcutBridgeRuntime` constructs only `ShortcutBridgeSettings`, `CGShortcutEventSink`, `ShortcutEmitter`, and `ShortcutHIDMonitor`. Its source file and tests must not reference:

```text
XiaomiBluetoothBridge
VirtualAudioOutput
LocalMicrophoneBridge
RemoteVoiceFunctionMapper
RemoteVoiceKeyMonitor
```

- [ ] **Step 5: Run HID and legacy regression tests**

Run:

```bash
xcrun swift test --filter ShortcutHIDRuntimeTests
xcrun swift test --filter RemoteButtonsTests
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/XiaomiRemoteBridgeMac/ShortcutHIDMonitor.swift Sources/XiaomiRemoteBridgeMac/ShortcutBridgeRuntime.swift Sources/XiaomiRemoteBridgeMac/KeyboardEventSuppressor.swift Tests/XiaomiRemoteBridgeMacTests/ShortcutHIDRuntimeTests.swift
git commit -m "feat: monitor RC003 as a shortcut controller"
```

### Task 6: Replace the Production App Shell and Settings Surface

**Files:**
- Create: `Sources/XiaomiRemoteBridgeMac/ShortcutBridgeAppModel.swift`
- Create: `Sources/XiaomiRemoteBridgeMac/ShortcutSettingsView.swift`
- Modify: `Sources/XiaomiRemoteBridgeMac/XiaomiRemoteBridgeMacApp.swift`
- Modify: `Sources/XiaomiRemoteBridgeMac/LaunchAtLoginManager.swift`
- Modify: `Sources/XiaomiRemoteBridgeMac/AppLogger.swift`
- Create: `Tests/XiaomiRemoteBridgeMacTests/ControllerOnlyWiringTests.swift`

**Interfaces:**
- Consumes: `ShortcutBridgeRuntime`, `ShortcutBridgeSettings`, `LaunchAtLoginManager`, `ShortcutRecorder`, and permission APIs.
- Produces: the only production app model and visible one-page settings UI.

- [ ] **Step 1: Add failing construction and source-contract tests**

Assert the production app delegate constructs `ShortcutBridgeAppModel`, not `BridgeAppModel`. Assert the new app model has no audio/BLE service references and the plist has no audio/Bluetooth privacy keys. Assert the logger path ends in `Library/Logs/RemoteShortcutBridge/runtime.log` and the login fallback bundle ID is the new ID.

- [ ] **Step 2: Run the red wiring test**

Run:

```bash
xcrun swift test --filter ControllerOnlyWiringTests
```

Expected: controller-only model and wiring are missing.

- [ ] **Step 3: Implement the app model**

Expose:

```swift
@Published private(set) var hidStatus: String
@Published private(set) var isConnected: Bool
@Published private(set) var inputMonitoringGranted: Bool
@Published private(set) var accessibilityGranted: Bool
let settings: ShortcutBridgeSettings
let launchAtLoginManager: LaunchAtLoginManager
func startIfNeeded()
func stop()
func refresh()
func setBinding(_:for:)
func requestInputMonitoringPermission()
func requestAccessibilityPermission()
func openLogFolder()
```

Changing or disabling a binding force-releases the previous held chord before saving.

- [ ] **Step 4: Implement the compact UI**

Create a vertically scrolling native SwiftUI window with:

- RC003 image and live connection/HID state;
- microphone row first, then the remaining 12 mapping rows;
- current shortcut, `重新录制`, and trash icon with tooltip;
- inline recorder state that supports modifier-only chords;
- Input Monitoring and Accessibility states with System Settings buttons;
- launch-at-login toggle, restore defaults, version, refresh, and logs.

Use `NSEvent.addLocalMonitorForEvents` only while recording, and remove every monitor on completion, cancellation, view disappearance, or app stop.

- [ ] **Step 5: Rewrite the app delegate**

Keep signal cleanup and one-way `NSHostingController` sizing. Rename menu text, tooltip, window title, autosave name, and accessibility descriptions. Menu items are only HID state, refresh, settings, logs, and quit.

- [ ] **Step 6: Run wiring and complete Swift tests**

Run:

```bash
xcrun swift test --filter ControllerOnlyWiringTests
xcrun swift test
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/XiaomiRemoteBridgeMac/ShortcutBridgeAppModel.swift Sources/XiaomiRemoteBridgeMac/ShortcutSettingsView.swift Sources/XiaomiRemoteBridgeMac/XiaomiRemoteBridgeMacApp.swift Sources/XiaomiRemoteBridgeMac/LaunchAtLoginManager.swift Sources/XiaomiRemoteBridgeMac/AppLogger.swift Tests/XiaomiRemoteBridgeMacTests/ControllerOnlyWiringTests.swift
git commit -m "feat: ship the controller-only macOS app"
```

### Task 7: Rename and Harden App and DMG Packaging

**Files:**
- Modify: `scripts/build-app.sh`
- Modify: `scripts/verify-app.sh`
- Modify: `scripts/build-dmg.sh`
- Modify: `scripts/verify-dmg.sh`
- Create: `scripts/create-local-signing-identity.sh`
- Modify: `Resources/首次安装说明.txt`
- Modify: `README.md`
- Create: `docs/LOCAL_RELEASE.md`

**Interfaces:**
- Consumes: the internal `XiaomiRemoteBridgeMac` binary and new plist.
- Produces: `dist/遥控快捷桥.app`, an Apple Silicon or verified universal DMG, checksum, and corresponding-source archive.

- [ ] **Step 1: Make packaging verification fail on the old identity**

Update verification expectations first:

```text
app path: dist/遥控快捷桥.app
bundle ID: com.kopwang.RemoteShortcutBridge
required resources: RC003 photo, icon, license, copyright, notices, README
forbidden privacy keys: NSMicrophoneUsageDescription, NSBluetoothAlwaysUsageDescription
forbidden user-visible strings: 小米遥控器桥接, Open Voice Bridge
```

Run:

```bash
scripts/verify-app.sh
```

Expected: it fails because the build script still creates the old app.

- [ ] **Step 2: Update build and signing**

Set `DISPLAY_NAME="遥控快捷桥"` and `LOCAL_SIGNING_IDENTITY="Remote Shortcut Bridge Local Code Signing"`. Keep the internal binary path unchanged. Remove ARN9 and DJI profiles from the installed app payload; include `xiaomi-rc003.json`, GPL files, and repository/source reference.

Add an idempotent identity helper that:

```bash
security find-identity -v -p codesigning
openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
  -subj "/CN=Remote Shortcut Bridge Local Code Signing/O=KopWang/" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -keyout "$TEMP_DIR/identity-key.pem" \
  -out "$TEMP_DIR/identity.pem"
P12_PASSWORD="$(openssl rand -hex 24)"
export P12_PASSWORD
openssl pkcs12 -export -legacy \
  -inkey "$TEMP_DIR/identity-key.pem" \
  -in "$TEMP_DIR/identity.pem" \
  -out "$TEMP_DIR/identity.p12" \
  -passout env:P12_PASSWORD
security import "$TEMP_DIR/identity.p12" \
  -k "$HOME/Library/Keychains/login.keychain-db" \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign
security add-trusted-cert -d -r trustRoot -p codeSign \
  -k "$HOME/Library/Keychains/login.keychain-db" \
  "$TEMP_DIR/identity.pem"
```

The script creates all certificate material in a mode-`0700` temporary
directory, supplies a generated one-process-only PKCS#12 password, securely
removes the directory on exit, and exits without changes when the exact valid
identity already exists. It never accepts or writes the user's login password.

- [ ] **Step 3: Update DMG packaging and documentation**

Name the release artifact:

```text
遥控快捷桥-0.1.0-test.1-macos.dmg
遥控快捷桥-0.1.0-test.1-macos.dmg.sha256
```

Installation notes explicitly state local signing, no notarization, Input Monitoring + Accessibility requirements, Typeless/DJI Mic Mini workflow, and no BlackHole requirement.

- [ ] **Step 4: Build and verify the app**

Run:

```bash
scripts/build-app.sh
scripts/verify-app.sh dist/遥控快捷桥.app
```

Expected: app allowlist, product metadata, resources, code signature, architecture, and forbidden-path scan pass.

- [ ] **Step 5: Try the universal build, then select an honest release architecture**

Run:

```bash
scripts/build-app.sh --universal
```

If both slices build, retain universal packaging. If the installed toolchain cannot build x86_64, switch the scripts to explicit Apple Silicon release mode and make `verify-dmg.sh` assert `arm64`; document that result.

- [ ] **Step 6: Build and verify the DMG**

Run:

```bash
scripts/build-dmg.sh
scripts/verify-dmg.sh
```

Expected: checksum, `hdiutil verify`, read-only mount, app signature, source archive, source allowlist, and local-path scans pass.

- [ ] **Step 7: Commit**

```bash
git add scripts Resources/首次安装说明.txt README.md docs/LOCAL_RELEASE.md
git commit -m "build: package the remote shortcut bridge test release"
```

### Task 8: Run the Full Automated Verification Gate

**Files:**
- Modify when a demonstrated regression requires it: files from Tasks 1-7 only.

**Interfaces:**
- Consumes: the complete source, app, and DMG.
- Produces: a clean automated acceptance record.

- [ ] **Step 1: Run format and repository checks**

Run:

```bash
git diff --check
scripts/test.sh
xcrun swift test
```

Expected: no whitespace defects and all self-tests/Swift tests pass.

- [ ] **Step 2: Rebuild from clean Swift artifacts**

Run:

```bash
xcrun swift package clean
scripts/build-app.sh
scripts/verify-app.sh
scripts/build-dmg.sh
scripts/verify-dmg.sh
```

Expected: reproducible app and DMG verification passes.

- [ ] **Step 3: Audit the production construction boundary**

Run:

```bash
rg -n "XiaomiBluetoothBridge|VirtualAudioOutput|LocalMicrophoneBridge|RemoteVoiceFunctionMapper|RemoteVoiceKeyMonitor" Sources/XiaomiRemoteBridgeMac/ShortcutBridgeAppModel.swift Sources/XiaomiRemoteBridgeMac/ShortcutBridgeRuntime.swift Sources/XiaomiRemoteBridgeMac/ShortcutSettingsView.swift Sources/XiaomiRemoteBridgeMac/XiaomiRemoteBridgeMacApp.swift
```

Expected: no matches.

- [ ] **Step 4: Inspect code-signing and linked frameworks**

Run:

```bash
codesign -dvvv dist/遥控快捷桥.app
codesign --verify --deep --strict --verbose=4 dist/遥控快捷桥.app
otool -L dist/遥控快捷桥.app/Contents/MacOS/XiaomiRemoteBridgeMac
```

Expected: stable local authority, valid designated requirement, and only expected system frameworks.

- [ ] **Step 5: Commit verification-only fixes, if any**

```bash
git add -u
git commit -m "fix: close release verification gaps"
```

Skip this commit when no files changed.

### Task 9: Create the Persistent Local Signing Identity and Install the App

**Files:**
- Create outside the repository: login-keychain certificate/private key.
- Install: `/Applications/遥控快捷桥.app`

**Interfaces:**
- Consumes: verified app and DMG.
- Produces: a stable locally signed installed app with a recorded designated requirement.

- [ ] **Step 1: Inspect existing identities**

Run:

```bash
security find-identity -v -p codesigning
```

Reuse the exact identity if present. Otherwise run:

```bash
scripts/create-local-signing-identity.sh
security find-identity -v -p codesigning
```

Expected: exactly one valid identity named `Remote Shortcut Bridge Local Code Signing`. The helper may trigger a macOS keychain authorization prompt, but it must never request the password through shell arguments or repository files.

- [ ] **Step 2: Rebuild with the named identity**

Run:

```bash
OVB_CODESIGN_IDENTITY="Remote Shortcut Bridge Local Code Signing" scripts/build-app.sh
codesign -dvvv dist/遥控快捷桥.app
```

Expected: `Authority=Remote Shortcut Bridge Local Code Signing`; ad-hoc fallback is not accepted for the installed build.

- [ ] **Step 3: Install without touching the old app**

Quit any development instance, copy the verified new app to `/Applications/遥控快捷桥.app`, remove quarantine only from this local build if present, and launch by its full path.

- [ ] **Step 4: Verify installed identity and process**

Run:

```bash
codesign --verify --deep --strict --verbose=4 /Applications/遥控快捷桥.app
mdls -name kMDItemCFBundleIdentifier /Applications/遥控快捷桥.app
pgrep -fl XiaomiRemoteBridgeMac
```

Expected: new bundle ID and a process whose executable resolves inside `/Applications/遥控快捷桥.app`.

### Task 10: Complete Real RC003, Typeless, DJI Mic Mini, and Login Acceptance

**Files:**
- Runtime evidence only; no source edits unless a reproduced defect requires TDD.

**Interfaces:**
- Consumes: installed new app, paired RC003, Typeless, and DJI Mic Mini.
- Produces: acceptance evidence that makes old-app and BlackHole cleanup safe.

- [ ] **Step 1: Grant the new app's two permissions**

Use the app's buttons and System Settings to enable `遥控快捷桥` under Input Monitoring and Accessibility. Relaunch if macOS requires it. Confirm the app reports both as granted.

- [ ] **Step 2: Verify HID-only connection**

Connect RC003 and confirm the new app reports the exact device as connected. Inspect the new runtime log and running processes to verify no BLE/ATVV/audio startup messages and no old app process handles the remote.

- [ ] **Step 3: Verify every physical control**

Use the UI to record a harmless test chord for each of the 13 rows, press/release its physical button, and confirm exactly one matching chord reaches a focused test surface. Restore defaults afterward.

- [ ] **Step 4: Verify Typeless with DJI Mic Mini**

Confirm Typeless's input is DJI Mic Mini and its toggle shortcut is `Control + Option`. With focus in a disposable text field:

1. press/release the RC003 microphone button once;
2. speak into DJI Mic Mini;
3. press/release the RC003 microphone button again;
4. confirm Typeless stops and inserts the transcription.

Confirm no BlackHole device is selected or required.

- [ ] **Step 5: Verify lifecycle cleanup**

Hold a mapped modifier chord, disconnect RC003, and verify modifiers are released. Reconnect and verify mapping resumes. Quit/reopen the app and verify mappings persist.

- [ ] **Step 6: Enable and verify login launch**

Enable launch at login in the app, inspect `SMAppService.mainApp.status`, and confirm macOS reports the new bundle's service as enabled or explicitly approved.

### Task 11: Publish the GitHub Test Release

**Files:**
- Repository refs and GitHub release only.

**Interfaces:**
- Consumes: accepted commit, verified DMG, and checksum.
- Produces: merged fork `main`, tag `v0.1.0-test.1`, and GitHub prerelease assets.

- [ ] **Step 1: Authenticate GitHub tooling**

Install GitHub CLI if absent and complete `gh auth login --web` against the user's existing GitHub session. Do not request or store a personal access token in repository files.

- [ ] **Step 2: Push and merge the verified branch**

Run:

```bash
git push --set-upstream origin feat/remote-shortcut-bridge
git fetch origin
git push origin feat/remote-shortcut-bridge:main
```

Expected: fork `main` advances to the accepted commit with no force push.

- [ ] **Step 3: Tag the exact accepted commit**

Run:

```bash
git tag -a v0.1.0-test.1 -m "Remote Shortcut Bridge v0.1.0 test 1"
git push origin v0.1.0-test.1
```

- [ ] **Step 4: Create the prerelease**

Use `gh release create v0.1.0-test.1` with the verified DMG and `.sha256`. Release notes state:

- locally signed, not Developer ID signed, not notarized;
- tested macOS version and Apple Silicon/universal architecture;
- RC003 model;
- microphone button default `Control + Option`;
- Typeless uses DJI Mic Mini directly;
- no RC003 audio path and no BlackHole dependency.

- [ ] **Step 5: Verify remote assets and checksums**

Run:

```bash
gh release view v0.1.0-test.1 --repo KopWang/open-voice-bridge-2
gh release download v0.1.0-test.1 --repo KopWang/open-voice-bridge-2 --pattern "*.sha256" --dir /private/tmp/remote-shortcut-release-check
```

Expected: prerelease is visible and checksum content matches the local verified DMG.

### Task 12: Remove the Legacy App and BlackHole, Restart, and Re-Verify

**Files:**
- Remove only the exact legacy paths listed in the design.

**Interfaces:**
- Consumes: successful Task 10 acceptance and published rollback artifact.
- Produces: a clean Mac with only Remote Shortcut Bridge active.

- [ ] **Step 1: Capture rollback facts**

Record the installed old app version, upstream commit `da2914e71aa908b30d747077f37ba8290b57c5c5`, new release URL/checksum, and old cleanup paths in a local release receipt.

- [ ] **Step 2: Disable and stop the old app**

Unregister the old `SMAppService`/LaunchAgent, quit the old process, and verify no executable under `/Applications/小米遥控器桥接.app` remains running.

- [ ] **Step 3: Remove only old app-owned data**

Remove when present:

```text
/Applications/小米遥控器桥接.app
~/Library/Preferences/com.kingwell.XiaomiRemoteBridgeMac.plist
~/Library/Logs/XiaomiRemoteBridgeMac/
~/Library/LaunchAgents/com.kingwell.XiaomiRemoteBridgeMac.plist
~/Library/LaunchAgents/com.kingwell.XiaomiRemoteBridgeMac.LaunchAtLogin.plist
```

Reset old TCC records with `tccutil reset` for `com.kingwell.XiaomiRemoteBridgeMac`. Do not reset the new bundle.

- [ ] **Step 4: Uninstall BlackHole 2ch**

Use Homebrew Cask's official uninstall/zap path for `blackhole-2ch`. Verify `/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver` is absent and CoreAudio no longer enumerates a BlackHole device. Do not remove other HAL drivers.

- [ ] **Step 5: Restart the Mac**

Restart after all cleanup so CoreAudio, login items, TCC, and HID state begin from a clean boot.

- [ ] **Step 6: Run final post-restart acceptance**

Verify:

```text
/Applications/遥控快捷桥.app exists and is correctly signed
old app and old processes are absent
BlackHole driver/device is absent
new app launched at login
RC003 reconnects
microphone button toggles Typeless twice
Typeless records from DJI Mic Mini and inserts text
new mappings persist
repository is clean and HEAD equals release tag
```

The task is complete only after every item passes or an unavoidable macOS UI gate is explicitly documented.
