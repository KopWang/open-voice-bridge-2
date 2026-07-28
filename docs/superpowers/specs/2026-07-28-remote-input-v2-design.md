# Remote Input V2 Design

## Proven failures

1. After `v0.1.1-test.2` restarted, the app logged an RC003 match but no
   button reports. The new code attempted an exclusive manager open, received
   `kIOReturnNotPrivileged`, and retried a monitored open on the same manager.
   That retry produced a false connected state with no input callbacks.
2. Shortcut recording used a session event tap. Mission Control can consume
   physical Control-arrow events before that layer.
3. The runtime supports overlapping output keys, but has no first-class model
   for a combination of remote input buttons.

## Runtime

- Open one freshly created RC003 `IOHIDManager` in monitored mode. Do not
  attempt an exclusive open on this unprivileged local build.
- Start native-event suppression at `cghidEventTap`, before macOS global
  shortcuts.
- Record shortcut input at `cghidEventTap`, suppressing every physical
  flags/key event for the complete recording interval.
- Log every accepted RC003 report with millisecond timestamps, raw bytes, and
  the full pressed-button set. Connected status alone is never treated as proof
  of working input.

## Keyboard semantics

The runtime owns one pressed-button set. A button-down emits a key-down and a
button-up emits the matching key-up. Modifiers therefore remain down while
another remote key is pressed. Events are ordered, as all keyboards are, but
their down/up intervals overlap exactly like a physical keyboard.

The device may serialize two physical buttons instead of reporting an
overlapping set. Raw report logging will distinguish that hardware limitation
from software behavior. When reports overlap, no timing heuristic is used.

## Explicit remote combinations

Settings store unordered remote-button chords containing two or more buttons.
Each chord maps to the same output types as a single button.

To distinguish a chord from its member singles:

- a member button with configured combinations waits up to 140 ms;
- if the configured pressed set forms a chord, its member single actions are
  suppressed and the chord output is held until every member is released;
- otherwise the pending single action begins after the window and remains held
  until physical release;
- a button mapped to a modifier and not participating in an explicit chord is
  never delayed.

The settings UI provides an explicit combination editor with two remote-button
selectors, output recording, modifier presets, and delete. Duplicate or
single-button combinations are rejected.

## Acceptance

- RC003 reports continue after every app restart.
- Recording physical Control+Up does not invoke Mission Control and saves the
  chord.
- Holding Menu=Control while pressing a direction produces overlapping
  Control-down, arrow-down/up, Control-up output.
- A configured two-button remote chord fires once and suppresses both singles.
- Existing single mappings and user preferences survive migration.
