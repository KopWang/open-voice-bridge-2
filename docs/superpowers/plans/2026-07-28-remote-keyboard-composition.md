# Remote Keyboard Composition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the RC003 behave as a composable physical keyboard, make Typeless's modifier shortcut reliable, and record shortcuts without triggering macOS global actions.

**Architecture:** Keep the verified HID report path. Replace per-binding modifier state with one remote keyboard state machine, add a deterministic modifier-shortcut pulse scheduler, capture shortcut recording through a temporary suppressing event tap, and request exclusive access at `IOHIDManagerOpen` before falling back to monitored mode.

**Tech Stack:** Swift 5 language mode, SwiftUI/AppKit, CoreGraphics event taps, IOKit HID, Swift Testing, local macOS code signing.

## Global Constraints

- No remote microphone, BLE audio, virtual audio device, or BlackHole dependency.
- Preserve bundle identifier `com.kopwang.RemoteShortcutBridge`.
- Default microphone binding remains `Control + Option`.
- Default Menu binding becomes held `Control`.
- Modifier shortcut pulse duration is exactly 120 milliseconds.
- Preserve user-custom Menu mappings; migrate only the untouched legacy Context Menu default.
- Release version is `0.1.1 (2)` with tag `v0.1.1-test.2`.
- The release remains universal, locally signed, and not notarized.

---

### Task 1: Global remote keyboard state and robust modifier pulse

**Files:**
- Modify: `Sources/XiaomiRemoteBridgeMac/ShortcutEmitter.swift`
- Modify: `Sources/XiaomiRemoteBridgeMac/ShortcutBinding.swift`
- Modify: `Tests/XiaomiRemoteBridgeMacTests/ShortcutEmitterTests.swift`

**Interfaces:**
- Produces: `ShortcutPulseScheduling.schedule(after:_:)`
- Produces: `DispatchShortcutPulseScheduler`
- Changes: `ShortcutEmitter.init(sink:scheduler:modifierPulseDuration:)`
- Preserves: `ShortcutEmitter.handle(_:button:binding:)`

- [ ] **Step 1: Write failing global-composition and pulse tests**

Add a manual scheduler and tests whose essential assertions are:

```swift
private final class Scheduler: ShortcutPulseScheduling {
    var scheduled: [(TimeInterval, () -> Void)] = []

    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) {
        scheduled.append((delay, action))
    }
}

@Test func heldRemoteModifierAppliesToAnotherRemoteKey() {
    let sink = Sink()
    let emitter = ShortcutEmitter(sink: sink)
    let control = KeyChord(modifiers: [.control], key: nil)!
    let up = KeyChord(
        modifiers: [],
        key: ShortcutKey(keyCode: 126, displayName: "Up Arrow")
    )!

    _ = emitter.handle(.down, button: .menu, binding: .chord(control))
    _ = emitter.handle(.down, button: .up, binding: .chord(up))
    _ = emitter.handle(.up, button: .up, binding: .chord(up))
    _ = emitter.handle(.up, button: .menu, binding: .chord(control))

    #expect(sink.events == [
        .modifier(.control, isDown: true, activeModifiers: [.control]),
        .key(up.key!, isDown: true, activeModifiers: [.control]),
        .key(up.key!, isDown: false, activeModifiers: [.control]),
        .modifier(.control, isDown: false, activeModifiers: []),
    ])
}

@Test func modifierOnlyShortcutUsesA120MillisecondPulse() {
    let sink = Sink()
    let scheduler = Scheduler()
    let emitter = ShortcutEmitter(sink: sink, scheduler: scheduler)

    _ = emitter.handle(.down, button: .microphone, binding: .chord(controlOption))
    _ = emitter.handle(.up, button: .microphone, binding: .chord(controlOption))

    #expect(scheduler.scheduled.count == 1)
    #expect(scheduler.scheduled[0].0 == 0.12)
    #expect(sink.events.count == 2)
    scheduler.scheduled[0].1()
    #expect(sink.events.count == 4)
}
```

Also cover overlapping owners and a forced release followed by a stale scheduled callback.

- [ ] **Step 2: Run the focused suite and verify RED**

Run:

```bash
./scripts/swift-package.sh test --filter "Shortcut emitter"
```

Expected: compilation fails because `ShortcutPulseScheduling` and the scheduler-injecting initializer do not exist, and composition expectations fail under per-chord flags.

- [ ] **Step 3: Implement the minimal global state machine**

In `ShortcutEmitter.swift`:

```swift
protocol ShortcutPulseScheduling {
    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void)
}

struct DispatchShortcutPulseScheduler: ShortcutPulseScheduling {
    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
    }
}
```

Track modifier and key owners by `RemoteButton`. Post a modifier only for its
first owner and release it only after its final owner. Pass the resulting
global modifier set to every key event. Treat a chord with `key == nil` and at
least two modifiers as a 120 ms pulse started on button-down; ignore its
physical button-up and invalidate its scheduled callback during replacement or
forced release.

Make `ShortcutKey` `Comparable` only if deterministic key release requires it;
its ordering must be by `keyCode`, then `displayName`.

- [ ] **Step 4: Run focused and full Swift tests**

Run:

```bash
./scripts/swift-package.sh test --filter "Shortcut emitter"
./scripts/swift-package.sh test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/XiaomiRemoteBridgeMac/ShortcutEmitter.swift \
  Sources/XiaomiRemoteBridgeMac/ShortcutBinding.swift \
  Tests/XiaomiRemoteBridgeMacTests/ShortcutEmitterTests.swift
git commit -m "fix: compose remote keys through global keyboard state"
```

### Task 2: Conflict-free shortcut capture

**Files:**
- Create: `Sources/XiaomiRemoteBridgeMac/ShortcutCaptureEventTap.swift`
- Modify: `Sources/XiaomiRemoteBridgeMac/ShortcutSettingsView.swift`
- Modify: `Package.swift`
- Create: `Tests/XiaomiRemoteBridgeMacTests/ShortcutCaptureEventTapTests.swift`

**Interfaces:**
- Produces: `ShortcutCaptureEventDisposition`
- Produces: `ShortcutCaptureEventPolicy.disposition(type:isSynthetic:)`
- Produces: `ShortcutCaptureEventTap.start(handler:) -> Bool`
- Produces: `ShortcutCaptureEventTap.stop()`
- Consumes: `ShortcutRecorder.handleFlagsChanged`, `handleKeyDown`, and `handleKeyUp`

- [ ] **Step 1: Write failing event-disposition tests**

```swift
@Test func physicalShortcutEventsAreCapturedAndSuppressed() {
    for type in [CGEventType.flagsChanged, .keyDown, .keyUp] {
        #expect(
            ShortcutCaptureEventPolicy.disposition(
                type: type,
                isSynthetic: false
            ) == .captureAndSuppress
        )
    }
}

@Test func syntheticAndTapDisabledEventsPassThrough() {
    #expect(
        ShortcutCaptureEventPolicy.disposition(
            type: .keyDown,
            isSynthetic: true
        ) == .passThrough
    )
    #expect(
        ShortcutCaptureEventPolicy.disposition(
            type: .tapDisabledByTimeout,
            isSynthetic: false
        ) == .reenableAndPassThrough
    )
}
```

- [ ] **Step 2: Run the new suite and verify RED**

Run:

```bash
./scripts/swift-package.sh test --filter "Shortcut capture event tap"
```

Expected: compilation fails because the policy and event-tap types do not exist.

- [ ] **Step 3: Implement and wire the temporary event tap**

Create a `.cgSessionEventTap` at `.headInsertEventTap` for `.flagsChanged`,
`.keyDown`, and `.keyUp`. Pass marked bridge events through. For physical
events, call the capture handler and return `nil`. Re-enable the tap for
`.tapDisabledByTimeout` and `.tapDisabledByUserInput`.

Replace `ShortcutCaptureModel.eventMonitors` with one
`ShortcutCaptureEventTap`. Convert `CGEvent.flags`, key code, and autorepeat
into the existing `ShortcutRecorder` calls. Start the tap before
`recorder.start()` and stop it from every finish/cancel/deinit path.

- [ ] **Step 4: Run focused tests and build**

Run:

```bash
./scripts/swift-package.sh test --filter "Shortcut capture event tap"
./scripts/swift-package.sh test --filter "Shortcut recorder"
./scripts/swift-package.sh build
```

Expected: all commands pass without warnings or errors.

- [ ] **Step 5: Commit**

```bash
git add Package.swift \
  Sources/XiaomiRemoteBridgeMac/ShortcutCaptureEventTap.swift \
  Sources/XiaomiRemoteBridgeMac/ShortcutSettingsView.swift \
  Tests/XiaomiRemoteBridgeMacTests/ShortcutCaptureEventTapTests.swift
git commit -m "fix: capture shortcuts before macOS global actions"
```

### Task 3: Exclusive HID manager opening

**Files:**
- Modify: `Sources/XiaomiRemoteBridgeMac/ShortcutHIDMonitor.swift`
- Modify: `Tests/XiaomiRemoteBridgeMacTests/ShortcutHIDRuntimeTests.swift`

**Interfaces:**
- Produces: `HIDManagerOpenMode`
- Produces: `HIDManagerOpenSelection.resolve(seizeResult:monitoredResult:)`
- Changes: manager opening is seize-first and monitored-fallback

- [ ] **Step 1: Write failing open-selection tests**

```swift
@Test func prefersExclusiveManagerOpen() {
    #expect(
        HIDManagerOpenSelection.resolve(
            seizeResult: kIOReturnSuccess,
            monitoredResult: kIOReturnError
        ) == .seized
    )
}

@Test func fallsBackToMonitoredAndReportsTotalFailure() {
    #expect(
        HIDManagerOpenSelection.resolve(
            seizeResult: kIOReturnExclusiveAccess,
            monitoredResult: kIOReturnSuccess
        ) == .monitored
    )
    #expect(
        HIDManagerOpenSelection.resolve(
            seizeResult: kIOReturnExclusiveAccess,
            monitoredResult: kIOReturnNotPermitted
        ) == .unavailable(kIOReturnNotPermitted)
    )
}
```

- [ ] **Step 2: Run the HID suite and verify RED**

Run:

```bash
./scripts/swift-package.sh test --filter "Controller-only HID runtime"
```

Expected: compilation fails because the selection types do not exist.

- [ ] **Step 3: Implement seize-first manager ownership**

Call:

```swift
let seizeResult = IOHIDManagerOpen(
    manager,
    IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
)
```

Only if it fails, call `IOHIDManagerOpen` with `kIOHIDOptionsTypeNone`.
Remember the successful mode. The manager has already propagated the open to
current and future devices, so `deviceDidMatch` must not call
`IOHIDDeviceOpen` again. Likewise, manager close owns device close.

Log both results on fallback:

```swift
AppLogger.shared.write(
    "HID EXCLUSIVE unavailable=\(seizeResult) fallback=\(monitoredResult)"
)
```

- [ ] **Step 4: Run focused tests and build**

Run:

```bash
./scripts/swift-package.sh test --filter "Controller-only HID runtime"
./scripts/swift-package.sh build
```

Expected: tests and build pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/XiaomiRemoteBridgeMac/ShortcutHIDMonitor.swift \
  Tests/XiaomiRemoteBridgeMacTests/ShortcutHIDRuntimeTests.swift
git commit -m "fix: seize the RC003 at HID manager open"
```

### Task 4: Modifier presets and Menu-to-Control migration

**Files:**
- Modify: `Sources/XiaomiRemoteBridgeMac/ShortcutBridgeSettings.swift`
- Modify: `Sources/XiaomiRemoteBridgeMac/ShortcutSettingsView.swift`
- Modify: `Tests/XiaomiRemoteBridgeMacTests/ShortcutBridgeSettingsTests.swift`

**Interfaces:**
- Changes: `ShortcutBridgeSettings.defaultBindings[.menu]`
- Adds persisted key: `shortcutMappingSchemaVersion = 2`

- [ ] **Step 1: Write failing default and migration tests**

Add tests proving:

```swift
#expect(
    ShortcutBridgeSettings.defaultBindings[.menu] ==
        .chord(KeyChord(modifiers: [.control], key: nil)!)
)
```

Seed a test `UserDefaults` suite with encoded
`.menu: .system(.contextMenu)` and no schema version; expect reload to migrate
Menu to Control. Seed another suite with `.menu: .disabled`; expect reload to
preserve Disabled.

- [ ] **Step 2: Run settings tests and verify RED**

Run:

```bash
./scripts/swift-package.sh test --filter "Shortcut bridge settings"
```

Expected: the new default and legacy migration assertions fail.

- [ ] **Step 3: Implement migration and preset menu**

During initialization, merge decoded saved bindings with defaults. When the
stored schema version is below 2, replace only
`.menu: .system(.contextMenu)` with the new single-Control chord, then store
schema version 2.

In each mapping row add a compact SwiftUI `Menu` with a keyboard icon. Its four
commands call:

```swift
model.setBinding(
    .chord(KeyChord(modifiers: [modifier], key: nil)!),
    for: button
)
```

for Control, Option, Shift, and Command. Keep recording and clearing actions.

- [ ] **Step 4: Run settings tests and build**

Run:

```bash
./scripts/swift-package.sh test --filter "Shortcut bridge settings"
./scripts/swift-package.sh build
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/XiaomiRemoteBridgeMac/ShortcutBridgeSettings.swift \
  Sources/XiaomiRemoteBridgeMac/ShortcutSettingsView.swift \
  Tests/XiaomiRemoteBridgeMacTests/ShortcutBridgeSettingsTests.swift
git commit -m "feat: map remote buttons as held modifiers"
```

### Task 5: Release identity and automated verification

**Files:**
- Modify: `Resources/Info.plist`
- Modify: `Resources/xiaomi-rc003-shortcut.json`
- Modify: `docs/LOCAL_RELEASE.md`
- Modify: `scripts/test.sh`

**Interfaces:**
- Produces: version `0.1.1 (2)`
- Produces: DMG `Remote-Shortcut-Bridge-0.1.1-test.2-macos.dmg`

- [ ] **Step 1: Update version and release contract**

Set `CFBundleShortVersionString` to `0.1.1` and `CFBundleVersion` to `2`.
Update the device profile and release notes with the global keyboard,
conflict-free recorder, and locally signed/non-notarized status.

Update `scripts/test.sh` identity assertions to `0.1.1` and `2`.

- [ ] **Step 2: Run complete verification**

Run:

```bash
./scripts/test.sh
./scripts/swift-package.sh test
git diff --check
RSB_REQUIRE_LOCAL_SIGNING=1 ./scripts/build-dmg.sh
RSB_REQUIRE_LOCAL_SIGNING=1 ./scripts/verify-dmg.sh
```

Expected: all tests pass, the app is `arm64` + `x86_64`, named local signing
verifies, and DMG checksum/structure verification passes.

- [ ] **Step 3: Commit**

```bash
git add Resources/Info.plist Resources/xiaomi-rc003-shortcut.json \
  docs/LOCAL_RELEASE.md scripts/test.sh
git commit -m "build: package remote keyboard test release"
```

### Task 6: Installed acceptance and GitHub prerelease

**Files:**
- Update local-only: `dist/LOCAL_INSTALL_RECEIPT.txt`

**Interfaces:**
- Consumes: signed universal app and DMG from Task 5
- Produces: installed `/Applications/遥控快捷桥.app`
- Produces: GitHub prerelease `v0.1.1-test.2`

- [ ] **Step 1: Preserve settings and replace the installed app**

Stop only the exact installed executable, replace the app with the signed
build, verify its designated requirement, and launch it. Do not reset the new
bundle's TCC entries.

- [ ] **Step 2: Verify runtime ownership**

Require fresh runtime log evidence for:

```text
HID PERMISSIONS input=true accessibility=true
HID START mode=controller_only
HID CONNECTED mode=seized
```

If the platform falls back, record the exact IOReturn value and do not claim
exclusive acceptance.

- [ ] **Step 3: Perform physical acceptance**

Use fresh runtime and Typeless history timestamps to verify:

- ten quick voice-key taps yield ten 120 ms emitted shortcut pulses;
- repeated start/stop operations create the expected Typeless sessions;
- those sessions use `DJI Mic Mini-DD2942`;
- Menu held with each direction emits Control plus that arrow;
- recording physical `Control + Up` completes while Mission Control stays put.

- [ ] **Step 4: Verify cleanup remains true**

Require BlackHole to be absent from Homebrew, the HAL driver directory, package
receipts, and `system_profiler SPAudioDataType`. Require the old app, process,
preferences, and login items to remain absent.

- [ ] **Step 5: Push and publish**

Push the feature branch and fast-forward fork `main`. Tag
`v0.1.1-test.2`, create a GitHub prerelease with the DMG and checksum, download
the remote assets into a temporary directory, verify SHA-256, and compare the
downloaded DMG byte-for-byte with the local artifact.

- [ ] **Step 6: Update the local receipt**

Record commit, tag, release URL, SHA-256, signing identity, automated test
counts, exclusive/monitored mode, physical acceptance evidence, Typeless/DJI
device evidence, and cleanup verification in
`dist/LOCAL_INSTALL_RECEIPT.txt`.
