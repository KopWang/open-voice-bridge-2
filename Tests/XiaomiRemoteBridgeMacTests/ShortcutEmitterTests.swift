import Foundation
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

    private final class Scheduler: ShortcutPulseScheduling {
        var scheduled: [(delay: TimeInterval, action: () -> Void)] = []

        func schedule(
            after delay: TimeInterval,
            _ action: @escaping () -> Void
        ) {
            scheduled.append((delay, action))
        }
    }

    private var controlOption: KeyChord {
        KeyChord(modifiers: [.control, .option], key: nil)!
    }

    @Test func emitsHeldModifierInDeterministicOrder() {
        let sink = Sink()
        let emitter = ShortcutEmitter(sink: sink)
        let control = KeyChord(modifiers: [.control], key: nil)!

        #expect(emitter.handle(
            .down,
            button: .microphone,
            binding: .chord(control)
        ))
        #expect(emitter.handle(
            .up,
            button: .microphone,
            binding: .chord(control)
        ))
        #expect(sink.events == [
            .modifier(.control, isDown: true, activeModifiers: [.control]),
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

    @Test func heldRemoteModifierAppliesToAnotherRemoteKey() {
        let sink = Sink()
        let emitter = ShortcutEmitter(sink: sink)
        let control = KeyChord(modifiers: [.control], key: nil)!
        let upKey = ShortcutKey(keyCode: 126, displayName: "Up Arrow")
        let up = KeyChord(modifiers: [], key: upKey)!

        _ = emitter.handle(.down, button: .menu, binding: .chord(control))
        _ = emitter.handle(.down, button: .up, binding: .chord(up))
        _ = emitter.handle(.up, button: .up, binding: .chord(up))
        _ = emitter.handle(.up, button: .menu, binding: .chord(control))

        #expect(sink.events == [
            .modifier(.control, isDown: true, activeModifiers: [.control]),
            .key(upKey, isDown: true, activeModifiers: [.control]),
            .key(upKey, isDown: false, activeModifiers: [.control]),
            .modifier(.control, isDown: false, activeModifiers: []),
        ])
    }

    @Test func overlappingModifierOwnersReleaseAfterTheFinalOwner() {
        let sink = Sink()
        let emitter = ShortcutEmitter(sink: sink)
        let control = KeyChord(modifiers: [.control], key: nil)!

        _ = emitter.handle(.down, button: .menu, binding: .chord(control))
        _ = emitter.handle(.down, button: .home, binding: .chord(control))
        _ = emitter.handle(.up, button: .menu, binding: .chord(control))
        #expect(sink.events == [
            .modifier(.control, isDown: true, activeModifiers: [.control]),
        ])
        _ = emitter.handle(.up, button: .home, binding: .chord(control))

        #expect(sink.events == [
            .modifier(.control, isDown: true, activeModifiers: [.control]),
            .modifier(.control, isDown: false, activeModifiers: []),
        ])
    }

    @Test func modifierOnlyShortcutUsesA250MillisecondPulse() {
        let sink = Sink()
        let scheduler = Scheduler()
        let emitter = ShortcutEmitter(sink: sink, scheduler: scheduler)

        _ = emitter.handle(
            .down,
            button: .microphone,
            binding: .chord(controlOption)
        )
        _ = emitter.handle(
            .up,
            button: .microphone,
            binding: .chord(controlOption)
        )

        #expect(scheduler.scheduled.count == 1)
        #expect(scheduler.scheduled[0].delay == 0.25)
        #expect(sink.events.count == 2)
        scheduler.scheduled[0].action()
        #expect(sink.events == [
            .modifier(.control, isDown: true, activeModifiers: [.control]),
            .modifier(.option, isDown: true, activeModifiers: [.control, .option]),
            .modifier(.option, isDown: false, activeModifiers: [.control]),
            .modifier(.control, isDown: false, activeModifiers: []),
        ])
    }

    @Test func forceReleaseInvalidatesPendingPulseCallback() {
        let sink = Sink()
        let scheduler = Scheduler()
        let emitter = ShortcutEmitter(sink: sink, scheduler: scheduler)

        _ = emitter.handle(
            .down,
            button: .microphone,
            binding: .chord(controlOption)
        )
        #expect(emitter.forceReleaseAll(reason: "test"))
        let eventsAfterRelease = sink.events
        scheduler.scheduled[0].action()

        #expect(sink.events == eventsAfterRelease)
        #expect(sink.events.count == 4)
    }
}
