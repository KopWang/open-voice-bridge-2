# Remote Shortcut Bridge Design

**Date:** 2026-07-27

**Repository:** `KopWang/open-voice-bridge-2`

**Upstream:** `nijez/open-voice-bridge`

**Release target:** `v0.1.0-test.1`

## Goal

Create a native macOS application that treats the Xiaomi Bluetooth Voice
Remote 2 Pro / RC003 only as a device-specific shortcut controller.

The application must let every physical remote button, including the
microphone button, emit a user-recorded macOS keyboard chord. The default
microphone-button chord is `Control + Option`, matching the user's Typeless
shortcut. Typeless continues to capture audio directly from DJI Mic Mini.

The product does not bridge, decode, capture, route, save, or upload audio.

## Product Identity

- Display name: `Remote Shortcut Bridge` / `遥控快捷桥`
- Bundle identifier: `com.kopwang.RemoteShortcutBridge`
- Initial version: `0.1.0`
- Initial build: `1`
- Test release tag: `v0.1.0-test.1`
- Local signing identity: `Remote Shortcut Bridge Local Code Signing`

The existing internal Swift package/target name may remain
`XiaomiRemoteBridgeMac` in the first release to avoid a broad mechanical
rename. User-visible product metadata, application paths, preferences, login
item identity, logs, build artifacts, and documentation must use the new
product identity.

The new application must coexist with the upstream application during
acceptance. It must not reuse `com.kingwell.XiaomiRemoteBridgeMac`.

## Scope

### Included

- Exact RC003 HID device matching.
- Raw HID button down/up handling.
- Input Monitoring and Accessibility permission handling.
- Reconnection and lifecycle handling.
- All 13 RC003 physical controls in one mapping model:
  - microphone
  - power
  - up
  - down
  - left
  - right
  - OK
  - back
  - volume up
  - volume down
  - home
  - menu
  - TV
- Arbitrary keyboard chords for every remote button.
- Modifier-only chords such as `Control + Option`.
- Modifier-plus-key chords such as `Command + Shift + K`.
- Disabled bindings.
- Shortcut recording UI.
- Persistent mappings.
- Login-at-launch support.
- Local build, persistent local signing, app verification, DMG packaging, DMG
  verification, installation, and GitHub test release.
- Real-device acceptance with RC003, Typeless, and DJI Mic Mini.
- Removal of the upstream application, its login item, preferences, logs, and
  permissions after the new application passes acceptance.
- Removal of BlackHole 2ch after the new application passes acceptance.

### Excluded

- RC003 microphone use.
- BLE GATT and ATVV runtime startup.
- Audio decoding or CoreAudio routing.
- BlackHole or any other virtual audio dependency.
- Local Mac microphone capture.
- Microphone permission.
- Audio diagnostics.
- DJI device discovery or configuration.
- Text macros.
- Multi-step key sequences.
- Shell scripts or application launching as button actions.
- LG Magic Remote support.
- Windows or Linux work.
- Developer ID signing, notarization, Sparkle, or another updater.

## User Workflow

1. The user pairs RC003 in macOS Bluetooth settings.
2. Remote Shortcut Bridge starts at login and watches for the exact RC003 HID
   identity.
3. Typeless remains configured to use DJI Mic Mini as its microphone.
4. The RC003 microphone button defaults to `Control + Option`.
5. Pressing and releasing the RC003 microphone button emits one complete
   `Control + Option` chord:
   - first press starts Typeless recording;
   - second press ends Typeless recording and inserts the transcription.
6. The user can record a different shortcut for any remote button from the
   settings window.

## Runtime Architecture

```text
RC003 Bluetooth HID
        |
        v
Exact HID identity matcher
        |
        v
Raw report parser and button-edge tracker
        |
        v
RemoteButton (13 physical controls)
        |
        v
Persisted ShortcutBinding
        |
        v
Shortcut emitter
        |
        v
macOS CGEvent stream
        |
        v
Typeless or another foreground application
```

Only the HID path starts in controller-only mode. The application must not
instantiate or start `XiaomiBluetoothBridge`, `VirtualAudioOutput`,
`LocalMicrophoneBridge`, audio diagnostics, or the F5-to-Fn hardware mapper.

The existing ATVV and audio source files may remain compiled in the first
release to minimize unrelated deletion risk, but no production runtime path or
user interface may reach them. Tests must prove that controller startup does
not construct or start those services.

## Device Identity

The first release supports RC003 only.

The HID matcher reuses the verified RC003 vendor ID, product ID, report ID, and
usage table from the upstream implementation. It must not match based only on a
fuzzy Bluetooth display name.

BLE Device Information Service model-number detection is not required for the
controller-only runtime. ARN9 support is not claimed in this release, even if
it happens to share some HID identity fields.

If no exact target is present, the application remains idle and displays
`等待遥控器`.

## Unified Button Model

The microphone button must become a first-class `RemoteButton` instead of a
separate fixed voice path.

Each physical button has:

- a stable identifier;
- a display name;
- a verified HID usage;
- a default `ShortcutBinding`;
- an optional native-event descriptor used only for precise suppression in
  compatibility mode.

The microphone button uses the verified keyboard F5 usage reported by RC003,
but it must not be remapped to Fn.

## Shortcut Data Model

```swift
struct KeyChord: Codable, Equatable {
    var modifiers: Set<KeyModifier>
    var key: KeyCode?
}

enum ShortcutBinding: Codable, Equatable {
    case disabled
    case chord(KeyChord)
    case system(SystemAction)
}
```

`KeyModifier` supports:

- Control
- Option
- Shift
- Command
- Fn only if a reliable injectable representation is proven by a test;
  otherwise it is not exposed in the first release.

`KeyChord.key == nil` is valid when at least one modifier exists. This is
required for `Control + Option`.

An empty chord is invalid and is represented as `.disabled`.

`SystemAction` is limited to the upstream implementation's already verified
media/system actions, such as system volume and show desktop. It exists so
those safe defaults do not have to be approximated with invented keyboard
chords. Every row can still be replaced by an arbitrary user-recorded
`KeyChord`.

Mappings persist in the new bundle's `UserDefaults`. Existing upstream
preferences are not imported because the action model and bundle identity are
different.

## Default Mappings

- microphone: `Control + Option`
- power: `Escape`
- up: `Up Arrow`
- down: `Down Arrow`
- left: `Left Arrow`
- right: `Right Arrow`
- OK: `Return`
- back: `Delete`
- volume up: upstream system volume-up action
- volume down: upstream system volume-down action
- home: upstream show-desktop action
- menu: upstream context-menu action
- TV: `Command + Tab`

Built-in media/system actions are represented by `SystemAction` when they
cannot be expressed reliably as a normal key chord. The UI still presents one
mapping row per physical button. Arbitrary user-recorded mappings use
`KeyChord`.

## Event Semantics

For a normal key chord:

1. On a target remote button down edge, press modifiers in a deterministic
   order and then press the primary key if present.
2. On the matching up edge, release the primary key first and modifiers in
   reverse order.
3. A repeated down without an intervening up does not emit a second chord.
4. A stray up does not emit events.

For a modifier-only chord:

1. Press each modifier on remote down.
2. Release each modifier in reverse order on remote up.
3. The resulting event sequence must be accepted by Typeless as one shortcut
   activation in real-device acceptance.

The emitter marks synthetic events with the existing private event-source
marker so the application's compatibility listener does not consume its own
output.

The application must force-release every held synthetic key when:

- the target HID device disappears;
- the HID reader loses permission;
- the reader generation changes;
- mappings are disabled or replaced;
- the bridge is paused;
- the application terminates.

This cleanup is mandatory because a stuck Control or Option modifier would
affect every application on the Mac.

## HID Read Policy

Reuse the upstream policy:

1. Prefer exact exclusive reading of RC003.
2. If macOS refuses exclusive access, use the existing compatibility monitor.
3. Suppress only native events correlated with an RC003 raw report.
4. Never suppress unrelated input from the built-in keyboard or other external
   keyboards.

The controller-only app does not need a separate voice-key observer. All 13
buttons must flow through one HID event pipeline.

## Permissions

Required:

- Input Monitoring
- Accessibility

Not required:

- Microphone
- application-level Bluetooth access

The UI must show the current state of both required permissions and provide a
button that opens the matching System Settings pane. It must fail closed when
either permission is missing.

The new bundle identity requires one new permission grant. The old bundle's
grants are not reused.

## Interface

The application remains a native menu-bar and Dock application with a compact
settings window.

The first and only functional page contains:

### Device

- product image or compact RC003 identity
- connection state
- HID reader state
- reconnect/refresh action when meaningful

### Shortcut Mappings

One row for each of the 13 buttons:

- physical button name
- formatted current binding
- `重新录制`
- `清除`

The microphone row is first and defaults to `Control + Option`.

### Shortcut Recorder

When `重新录制` is selected:

1. The row enters a recording state.
2. The window displays the currently held modifiers and primary key.
3. Releasing all keys saves a non-empty chord.
4. Modifier-only chords save successfully.
5. Escape cancels without changing the previous value.
6. The recorder ignores synthetic events emitted by this application.
7. The recorder does not save mouse clicks, text, or multi-step sequences.

### Application

- Input Monitoring state and action
- Accessibility state and action
- launch-at-login checkbox
- restore-default-mappings action
- application version

The window contains no audio-device selector, gain control, microphone
permission, ATVV status, audio diagnostics, device-profile switcher, or
BlackHole link.

## Logging and Privacy

The application logs:

- application start/stop;
- target attached/detached;
- reader mode and health;
- permission category changes;
- mapping activation failures;
- forced-release reason.

It does not log:

- typed content;
- the active application;
- the user's shortcut values;
- device addresses or UUIDs;
- microphone or audio data.

Logs use a new directory under:

`~/Library/Logs/RemoteShortcutBridge/`

## Testing

### Unit and Contract Tests

- RC003 report parsing includes the microphone F5 usage.
- All 13 physical buttons have stable identifiers and defaults.
- `KeyChord` accepts modifier-only chords.
- Empty chords are rejected/disabled.
- Codable round trips preserve every modifier and supported key.
- Recorder captures modifier-only and modifier-plus-key chords.
- Escape cancels recording.
- Duplicate down and stray up edges are ignored.
- Event ordering is deterministic.
- Device removal force-releases held modifiers.
- Permission loss force-releases held modifiers.
- Mapping replacement force-releases the old chord.
- Synthetic events are marked and ignored by compatibility monitoring.
- Controller startup does not start BLE, ATVV, CoreAudio, or microphone
  services.
- New product metadata and bundle paths are correct.
- Old product names are absent from user-visible controller-only surfaces,
  except attribution and migration documentation.

### Build Verification

- Swift tests and repository self-tests pass.
- Native Apple Silicon build passes on the target Mac.
- Universal build passes if the installed toolchain can produce both slices;
  otherwise the test release explicitly states Apple Silicon only.
- `.app` structure matches the packaging allowlist.
- resources and GPL notices are present.
- local codesign verification passes.
- no forbidden local paths are embedded.
- DMG verification passes.

### Real-Device Acceptance

- RC003 connects without starting ATVV.
- All 13 buttons are visible and recordable.
- Typeless microphone is DJI Mic Mini.
- First microphone-button press starts Typeless.
- Second microphone-button press ends Typeless and inserts text.
- No BlackHole device is selected or required.
- Remote disconnect during a held modifier does not leave modifiers stuck.
- App restart preserves mappings.
- Remote reconnect resumes monitoring.
- Mac restart launches the app and resumes monitoring.
- Built-in keyboard and unrelated Bluetooth devices remain unaffected.

## Local Signing and Packaging

Create or reuse a persistent self-signed code-signing identity named:

`Remote Shortcut Bridge Local Code Signing`

The private key remains in the user's login keychain and is never committed or
uploaded.

The local installed application and locally built DMG use this identity to
keep the designated requirement stable across rebuilds and reduce repeated TCC
permission churn.

The GitHub test release is explicitly:

- not Developer ID signed;
- not notarized;
- intended primarily for this Mac;
- expected to require manual Gatekeeper approval on another Mac.

The DMG contains:

- `遥控快捷桥.app`
- installation notes
- `LICENSE`
- `THIRD_PARTY_NOTICES.md`
- a source/repository reference satisfying GPL source availability

## Installation and Migration

Migration is acceptance-gated:

1. Build and verify the new app.
2. Install `/Applications/遥控快捷桥.app`.
3. Grant the new bundle Input Monitoring and Accessibility permissions.
4. Pair/connect RC003 and complete Typeless + DJI Mic Mini acceptance.
5. Enable and verify the new login item.
6. Only after acceptance, unregister the old login item.
7. Quit the old application.
8. Remove `/Applications/小米遥控器桥接.app`.
9. Remove old preferences, logs, and legacy LaunchAgent files.
10. Reset old TCC records for `com.kingwell.XiaomiRemoteBridgeMac`.
11. Uninstall Homebrew Cask `blackhole-2ch`.
12. Verify the BlackHole driver and CoreAudio device are gone.
13. Restart CoreAudio or the Mac when required.
14. Re-verify the new app after the final restart.

Old-path cleanup includes, when present:

- `/Applications/小米遥控器桥接.app`
- `~/Library/Preferences/com.kingwell.XiaomiRemoteBridgeMac.plist`
- `~/Library/Logs/XiaomiRemoteBridgeMac/`
- `~/Library/LaunchAgents/com.kingwell.XiaomiRemoteBridgeMac.plist`
- old TCC records for `com.kingwell.XiaomiRemoteBridgeMac`
- `/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver` via the official Homebrew
  Cask uninstaller

The cleanup must not delete unrelated audio drivers or unrelated login items.

## Release

After local acceptance:

1. Commit the complete implementation.
2. Push the feature branch to `KopWang/open-voice-bridge-2`.
3. Merge to the fork's `main` after verification.
4. Tag `v0.1.0-test.1`.
5. Create a GitHub prerelease.
6. Attach the verified DMG and checksums.
7. State the lack of Developer ID signing/notarization.
8. Include tested macOS version, architecture, RC003 model, Typeless workflow,
   and DJI Mic Mini as the accepted audio source.

## Rollback

Before removing the old installation, retain:

- the upstream repository and tag;
- the verified new DMG;
- the new release tag;
- a record of the old application version and cleanup paths.

If real-device acceptance fails before cleanup, keep the old app installed and
restore its login item. If failure occurs after cleanup, the upstream app can
be rebuilt or reinstalled from its pinned source revision.

## Completion Criteria

The work is complete only when:

- code and automated tests pass;
- the application and DMG verify;
- the locally signed app is installed;
- RC003 triggers Typeless through the configured shortcut;
- Typeless records from DJI Mic Mini and inserts text;
- the new login item survives a restart;
- the old app and old login item are absent;
- BlackHole is absent from both disk and CoreAudio enumeration;
- the GitHub prerelease and checksum are available;
- the fork's repository state is clean and traceable to the installed build.
