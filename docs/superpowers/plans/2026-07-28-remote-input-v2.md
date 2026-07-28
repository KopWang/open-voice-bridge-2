# Remote Input V2 Implementation Plan

1. Add failing runtime tests that require one monitored manager open and a HID
   event-tap location; implement both fixes and report-level logging.
2. Add failing tests for an unordered remote-button chord model, persistence,
   duplicate validation, and migration; implement the settings model.
3. Add failing state-machine tests for chord recognition, single-key deferral,
   suppression, release, and real modifier overlap; route HID snapshots through
   the state machine.
4. Add the combination editor to the native settings UI and retain existing
   single-button controls.
5. Bump to `0.1.2 (3)`, run all tests, build and verify a universal locally
   signed DMG, replace the installed app, and verify reports after restart.
6. Verify physical shortcut capture at the HID layer, preserve user settings,
   push `main`, and publish `v0.1.2-test.3`.
