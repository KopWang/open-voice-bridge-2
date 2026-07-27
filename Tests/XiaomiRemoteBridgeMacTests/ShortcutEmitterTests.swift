import Testing
@testable import XiaomiRemoteBridgeMac

@Suite("Shortcut emitter")
struct ShortcutEmitterTests {
    private final class Sink: ShortcutEventSink {
        var events: [ShortcutEvent] = []
        var failingIndex: Int?
        private var index = 0

        func post(_ event: ShortcutEvent) -> Bool {
            defer { index += 1 }
            guard index != failingIndex else { return false }
            events.append(event)
            return true
        }
    }

    private var controlOption: KeyChord {
        KeyChord(modifiers: [.control, .option], key: nil)!
    }

    @Test func emitsModifierOnlyChordInDeterministicOrder() {
        let sink = Sink()
        let emitter = ShortcutEmitter(sink: sink)

        #expect(emitter.handle(
            .down,
            button: .microphone,
            binding: .chord(controlOption)
        ))
        #expect(emitter.handle(
            .up,
            button: .microphone,
            binding: .chord(controlOption)
        ))
        #expect(sink.events == [
            .modifier(.control, isDown: true, activeModifiers: [.control]),
            .modifier(.option, isDown: true, activeModifiers: [.control, .option]),
            .modifier(.option, isDown: false, activeModifiers: [.control]),
            .modifier(.control, isDown: false, activeModifiers: []),
        ])
    }

    @Test func ignoresDuplicateDownAndStrayUp() {
        let sink = Sink()
        let emitter = ShortcutEmitter(sink: sink)

        #expect(emitter.handle(.up, button: .microphone, binding: .chord(controlOption)))
        #expect(emitter.handle(.down, button: .microphone, binding: .chord(controlOption)))
        #expect(emitter.handle(.down, button: .microphone, binding: .chord(controlOption)))
        #expect(sink.events.count == 2)
    }

    @Test func forceReleaseAndReplacementBalanceHeldModifiers() {
        let sink = Sink()
        let emitter = ShortcutEmitter(sink: sink)

        _ = emitter.handle(.down, button: .microphone, binding: .chord(controlOption))
        #expect(emitter.replaceBinding(for: .microphone))
        _ = emitter.handle(.down, button: .microphone, binding: .chord(controlOption))
        #expect(emitter.forceReleaseAll(reason: "test"))
        #expect(sink.events.filter { event in
            event == .modifier(.control, isDown: false, activeModifiers: [])
        }.count == 2)
    }

    @Test func rollsBackPartialPressFailure() {
        let sink = Sink()
        sink.failingIndex = 1
        let emitter = ShortcutEmitter(sink: sink)

        #expect(!emitter.handle(
            .down,
            button: .microphone,
            binding: .chord(controlOption)
        ))
        #expect(sink.events == [
            .modifier(.control, isDown: true, activeModifiers: [.control]),
            .modifier(.control, isDown: false, activeModifiers: []),
        ])
    }
}
