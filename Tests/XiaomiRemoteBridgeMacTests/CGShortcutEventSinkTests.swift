import CoreGraphics
import Testing
@testable import XiaomiRemoteBridgeMac

@Suite("Quartz shortcut event sink")
struct CGShortcutEventSinkTests {
    @Test func modifierEdgesUseFlagsChangedEvents() throws {
        let source = try #require(CGEventSource(stateID: .hidSystemState))
        let down = try #require(
            CGShortcutEventSink.makeKeyboardEvent(
                for: .modifier(
                    .control,
                    isDown: true,
                    activeModifiers: [.control]
                ),
                source: source
            )
        )
        let up = try #require(
            CGShortcutEventSink.makeKeyboardEvent(
                for: .modifier(
                    .control,
                    isDown: false,
                    activeModifiers: []
                ),
                source: source
            )
        )

        #expect(down.type == .flagsChanged)
        #expect(up.type == .flagsChanged)
    }

    @Test func ordinaryKeysKeepTheirDownAndUpEventTypes() throws {
        let source = try #require(CGEventSource(stateID: .hidSystemState))
        let key = ShortcutKey(keyCode: 126, displayName: "Up Arrow")
        let down = try #require(
            CGShortcutEventSink.makeKeyboardEvent(
                for: .key(
                    key,
                    isDown: true,
                    activeModifiers: [.control]
                ),
                source: source
            )
        )
        let up = try #require(
            CGShortcutEventSink.makeKeyboardEvent(
                for: .key(
                    key,
                    isDown: false,
                    activeModifiers: [.control]
                ),
                source: source
            )
        )

        #expect(down.type == .keyDown)
        #expect(up.type == .keyUp)
    }
}
