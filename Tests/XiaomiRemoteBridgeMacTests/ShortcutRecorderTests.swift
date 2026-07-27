import Testing
@testable import XiaomiRemoteBridgeMac

@Suite("Shortcut recorder")
struct ShortcutRecorderTests {
    @Test func capturesLargestModifierOnlyChord() {
        let recorder = ShortcutRecorder()
        var completed: KeyChord?
        recorder.onComplete = { completed = $0 }

        recorder.start()
        recorder.handleFlagsChanged([.control])
        recorder.handleFlagsChanged([.control, .option])
        recorder.handleFlagsChanged([.control])
        recorder.handleFlagsChanged([])

        #expect(completed == KeyChord(modifiers: [.control, .option], key: nil))
    }

    @Test func capturesModifierPlusKeyAfterAllKeysRelease() {
        let recorder = ShortcutRecorder()
        let key = ShortcutKey(keyCode: 40, displayName: "K")
        var completed: KeyChord?
        recorder.onComplete = { completed = $0 }

        recorder.start()
        recorder.handleFlagsChanged([.command, .shift])
        recorder.handleKeyDown(key, modifiers: [.command, .shift])
        recorder.handleKeyUp(key, modifiers: [.command, .shift])
        #expect(completed == nil)
        recorder.handleFlagsChanged([])

        #expect(completed == KeyChord(
            modifiers: [.command, .shift],
            key: key
        ))
    }

    @Test func escapeCancelsAndSyntheticEventsAreIgnored() {
        let recorder = ShortcutRecorder()
        var cancelled = false
        var completed: KeyChord?
        recorder.onCancel = { cancelled = true }
        recorder.onComplete = { completed = $0 }

        recorder.start()
        recorder.handleFlagsChanged([.command], isSynthetic: true)
        recorder.handleKeyDown(
            ShortcutKey(keyCode: 53, displayName: "Escape"),
            modifiers: []
        )

        #expect(cancelled)
        #expect(completed == nil)
    }

    @Test func ignoresRepeatAndSecondPrimaryKey() {
        let recorder = ShortcutRecorder()
        let first = ShortcutKey(keyCode: 0, displayName: "A")
        let second = ShortcutKey(keyCode: 11, displayName: "B")
        var completed: KeyChord?
        recorder.onComplete = { completed = $0 }

        recorder.start()
        recorder.handleKeyDown(first, modifiers: [], isRepeat: true)
        recorder.handleKeyDown(first, modifiers: [])
        recorder.handleKeyDown(second, modifiers: [])
        recorder.handleKeyUp(second, modifiers: [])
        #expect(completed == nil)
        recorder.handleKeyUp(first, modifiers: [])

        #expect(completed == KeyChord(modifiers: [], key: first))
    }
}
