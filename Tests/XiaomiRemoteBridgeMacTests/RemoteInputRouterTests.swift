import Foundation
import Testing
@testable import XiaomiRemoteBridgeMac

@Suite("Remote input router")
struct RemoteInputRouterTests {
    private final class Sink: ShortcutEventSink {
        var events: [ShortcutEvent] = []

        func post(_ event: ShortcutEvent) -> Bool {
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

    @Test func overlappingRemoteButtonsBehaveLikeAKeyboard() throws {
        let fixture = try makeFixture()

        _ = fixture.router.update(pressed: [.menu])
        _ = fixture.router.update(pressed: [.menu, .up])
        _ = fixture.router.update(pressed: [.menu])
        _ = fixture.router.update(pressed: [])

        let up = ShortcutKey(keyCode: 126, displayName: "Up Arrow")
        #expect(fixture.sink.events == [
            .modifier(.control, isDown: true, activeModifiers: [.control]),
            .key(up, isDown: true, activeModifiers: [.control]),
            .key(up, isDown: false, activeModifiers: [.control]),
            .modifier(.control, isDown: false, activeModifiers: []),
        ])
    }

    @Test func explicitCombinationSuppressesItsSingleButtons() throws {
        let fixture = try makeFixture()
        let input = try #require(
            RemoteButtonChord(buttons: [.menu, .up])
        )
        let outputKey = ShortcutKey(keyCode: 40, displayName: "K")
        let output = try #require(
            KeyChord(modifiers: [.command], key: outputKey)
        )
        fixture.settings.setCombinationBinding(.chord(output), for: input)

        _ = fixture.router.update(pressed: [.menu])
        _ = fixture.router.update(pressed: [.menu, .up])
        _ = fixture.router.update(pressed: [.menu])
        _ = fixture.router.update(pressed: [])

        #expect(fixture.scheduler.scheduled.count == 2)
        #expect(fixture.scheduler.scheduled.allSatisfy { $0.delay == 0.5 })
        #expect(fixture.sink.events == [
            .modifier(.command, isDown: true, activeModifiers: [.command]),
            .key(outputKey, isDown: true, activeModifiers: [.command]),
            .key(outputKey, isDown: false, activeModifiers: [.command]),
            .modifier(.command, isDown: false, activeModifiers: []),
        ])
    }

    @Test func chordMemberFallsBackToItsSingleMappingAfterWindow() throws {
        let fixture = try makeFixture()
        let input = try #require(
            RemoteButtonChord(buttons: [.menu, .up])
        )
        fixture.settings.setCombinationBinding(.disabled, for: input)

        _ = fixture.router.update(pressed: [.menu])
        fixture.scheduler.scheduled[0].action()
        _ = fixture.router.update(pressed: [])
        fixture.scheduler.scheduled[1].action()

        #expect(fixture.sink.events == [
            .modifier(.control, isDown: true, activeModifiers: [.control]),
            .modifier(.control, isDown: false, activeModifiers: []),
        ])
    }

    @Test func serializedReportsResolveAnExplicitCombination() throws {
        let fixture = try makeFixture()
        let input = try #require(
            RemoteButtonChord(buttons: [.menu, .up])
        )
        fixture.settings.setCombinationBinding(.system(.showDesktop), for: input)

        _ = fixture.router.update(pressed: [.menu])
        _ = fixture.router.update(pressed: [.up])
        _ = fixture.router.update(pressed: [])

        #expect(fixture.sink.events == [.system(.showDesktop)])
    }

    @Test func serializedButtonsOutsideTheWindowRemainSingles() throws {
        let fixture = try makeFixture()
        let input = try #require(
            RemoteButtonChord(buttons: [.ok, .up])
        )
        fixture.settings.setCombinationBinding(.system(.showDesktop), for: input)

        _ = fixture.router.update(pressed: [.ok])
        _ = fixture.router.update(pressed: [])
        fixture.scheduler.scheduled[0].action()
        _ = fixture.router.update(pressed: [.up])
        _ = fixture.router.update(pressed: [])
        fixture.scheduler.scheduled[1].action()

        let enter = ShortcutKey(keyCode: 36, displayName: "Return")
        let up = ShortcutKey(keyCode: 126, displayName: "Up Arrow")
        #expect(fixture.sink.events == [
            .key(enter, isDown: true, activeModifiers: []),
            .key(enter, isDown: false, activeModifiers: []),
            .key(up, isDown: true, activeModifiers: []),
            .key(up, isDown: false, activeModifiers: []),
        ])
    }

    @Test func serializedModifierThenKeyStillOverlapsAtTheOutput() throws {
        let fixture = try makeFixture()

        _ = fixture.router.update(pressed: [.menu])
        _ = fixture.router.update(pressed: [])
        _ = fixture.router.update(pressed: [.up])
        _ = fixture.router.update(pressed: [])

        let up = ShortcutKey(keyCode: 126, displayName: "Up Arrow")
        #expect(fixture.scheduler.scheduled.count == 1)
        #expect(fixture.scheduler.scheduled[0].delay == 0.5)
        #expect(fixture.sink.events == [
            .modifier(.control, isDown: true, activeModifiers: [.control]),
            .key(up, isDown: true, activeModifiers: [.control]),
            .key(up, isDown: false, activeModifiers: [.control]),
            .modifier(.control, isDown: false, activeModifiers: []),
        ])
    }

    @Test func releasedModifierEndsWhenNoFollowerArrives() throws {
        let fixture = try makeFixture()

        _ = fixture.router.update(pressed: [.menu])
        _ = fixture.router.update(pressed: [])
        #expect(fixture.sink.events.count == 1)
        fixture.scheduler.scheduled[0].action()

        #expect(fixture.sink.events == [
            .modifier(.control, isDown: true, activeModifiers: [.control]),
            .modifier(.control, isDown: false, activeModifiers: []),
        ])
    }

    private func makeFixture() throws -> (
        router: RemoteInputRouter,
        settings: ShortcutBridgeSettings,
        sink: Sink,
        scheduler: Scheduler
    ) {
        let suiteName = "RemoteInputRouterTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let settings = ShortcutBridgeSettings(defaults: defaults)
        let sink = Sink()
        let emitter = ShortcutEmitter(sink: sink)
        let scheduler = Scheduler()
        let router = RemoteInputRouter(
            settings: settings,
            emitter: emitter,
            scheduler: scheduler
        )
        return (router, settings, sink, scheduler)
    }
}
