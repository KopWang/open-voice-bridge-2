# Remote Keyboard Composition Design

Date: 2026-07-28

## Problem

The first controller-only release reliably receives RC003 HID reports, but the
translation layer does not yet behave like a physical keyboard:

1. Very short modifier-only RC003 presses produce equally short synthetic
   `Control + Option` pulses. Typeless ignores many of these pulses.
2. Shortcut recording uses local `NSEvent` monitors. macOS global shortcuts,
   such as `Control + Up`, can be consumed by Mission Control before the app
   records them.
3. Each remote binding calculates its modifier flags independently. Holding a
   remote button mapped to `Control` and pressing a second button mapped to
   `Up Arrow` therefore emits the arrow without the globally held Control flag.
4. The HID manager opens devices non-exclusively and only attempts to seize the
   device after the manager has already propagated that non-exclusive open.
   The installed app consequently runs in monitored mode and must race the
   original RC003 keyboard events.

Runtime evidence shows every tested physical button edge entering the app.
Typeless history shows only a subset of the resulting short modifier gestures
starting or stopping sessions. Apple IOHID headers specify that exclusive
manager access must be requested through `IOHIDManagerOpen` with
`kIOHIDOptionsTypeSeizeDevice`.

## Considered Approaches

### 1. Extend the existing HID bridge into a keyboard state machine

Keep the verified RC003 HID parser and add global modifier/key ownership,
exclusive-manager-first opening, robust shortcut pulses, and a system-level
recording event tap.

This is the recommended approach. It preserves the working device integration,
requires no driver or third-party dependency, and directly addresses all four
root causes.

### 2. Remap the RC003 native macOS keyboard events

Listen only to macOS keyboard events and rewrite known key codes. This cannot
reliably distinguish RC003 events from the built-in or another external
keyboard, and the RC003 Back control has no dependable native keyboard event.

### 3. Install a virtual keyboard driver or require Karabiner-Elements

A driver-level virtual keyboard would provide strong isolation, but it adds a
privileged system extension, another permission/install lifecycle, and a
third-party runtime dependency. That is disproportionate for this app.

## Design

### Global remote keyboard state

`ShortcutEmitter` will maintain one state for the whole remote:

- active remote-button bindings;
- modifier owners, keyed by `KeyModifier`;
- key owners, keyed by `ShortcutKey`;
- the current global modifier set.

The first remote owner of a modifier emits modifier-down; the last owner emits
modifier-up. Key events always include the global modifier set. This makes a
button mapped to `Control` compose naturally with remote Up, Down, Left, Right,
or any other mapped key. Duplicate reports and overlapping mappings remain
balanced.

Changing a binding, disconnecting the remote, losing permissions, or stopping
the app releases every owned key and modifier.

### Robust modifier shortcut pulse

A modifier-only chord containing two or more modifiers is treated as a shortcut
pulse rather than a held keyboard modifier. On button-down it presses the chord,
keeps it active for 120 milliseconds, then releases it. The physical button-up
does not shorten the pulse.

A single modifier remains a true held keyboard key. This distinction makes the
default Typeless `Control + Option` gesture reliable without making a remote
`Control` key linger after release.

The pulse scheduler is injected into `ShortcutEmitter` so timing behavior,
forced release, and duplicate edges are deterministic in tests.

### Conflict-free shortcut recording

Replace local `NSEvent` recording monitors with a temporary
`CGEventTap` at the head of the session event stream while recording:

- capture flags-changed, key-down, and key-up;
- swallow captured physical events so Mission Control and other global
  shortcuts do not run;
- pass through this app's marked synthetic events;
- re-enable the tap if macOS disables it for timeout or user input;
- remove the tap immediately on completion, cancellation, or window close.

The existing pure `ShortcutRecorder` remains the chord state machine.

### Exclusive HID opening

Open the filtered `IOHIDManager` with
`kIOHIDOptionsTypeSeizeDevice` first. If that fails, close the attempt and open
the manager in monitored mode as a compatibility fallback. Device callbacks
must not open the already manager-opened device a second time.

The UI and runtime log continue to state honestly whether the connection is
exclusive or monitored.

### Mapping UI and defaults

Add a compact keyboard preset menu to each mapping row with:

- Control
- Option
- Shift
- Command

Arbitrary shortcut recording and clearing remain available.

The default Menu-button mapping changes from Context Menu to held Control.
Settings migration changes only an untouched legacy Menu default; a user-custom
Menu mapping is preserved.

### Release identity

The repaired local test release is version `0.1.1 (2)` and tag
`v0.1.1-test.2`. It remains locally signed, universal, and not notarized.

## Verification

Automated tests must prove:

- a held remote Control modifies another remote arrow key;
- overlapping modifier and key owners release only after their final owner;
- `Control + Option` has a minimum 120 ms pulse;
- forced release invalidates pending pulse callbacks;
- recorder input classification captures and suppresses physical shortcut
  events while passing synthetic bridge events;
- HID open selection prefers exclusive manager mode and falls back honestly;
- settings migration makes an untouched legacy Menu mapping Control while
  preserving custom mappings.

Installed acceptance must prove:

- the app restarts in exclusive mode when the platform permits it;
- ten quick voice-button taps produce ten observable `Control + Option` pulses;
- repeated quick Typeless start/stop operations no longer require long presses;
- holding Menu while pressing Up, Down, Left, and Right produces Control-arrow
  combinations;
- recording `Control + Up` does not invoke Mission Control;
- DJI Mic Mini remains Typeless's selected input and BlackHole remains absent.
