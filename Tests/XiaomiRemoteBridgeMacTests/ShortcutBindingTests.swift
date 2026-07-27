import Foundation
import Testing
@testable import XiaomiRemoteBridgeMac

@Suite("Shortcut bindings")
struct ShortcutBindingTests {
    @Test func acceptsModifierOnlyChordAndRejectsEmptyChord() {
        let modifierOnly = KeyChord(modifiers: [.control, .option], key: nil)

        #expect(modifierOnly?.displayName == "Control + Option")
        #expect(KeyChord(modifiers: [], key: nil) == nil)
    }

    @Test func formatsModifiersInDeterministicOrder() {
        let chord = KeyChord(
            modifiers: [.command, .control, .shift, .option],
            key: ShortcutKey(keyCode: 40, displayName: "K")
        )

        #expect(chord?.displayName == "Control + Option + Shift + Command + K")
    }

    @Test func roundTripsEveryBindingKind() throws {
        let bindings: [ShortcutBinding] = [
            .disabled,
            .chord(try #require(KeyChord(modifiers: [.control, .option], key: nil))),
            .system(.volumeUp),
        ]

        let data = try JSONEncoder().encode(bindings)
        #expect(try JSONDecoder().decode([ShortcutBinding].self, from: data) == bindings)
    }

    @Test func rejectsDecodedEmptyChord() {
        let data = Data(
            #"{"kind":"chord","chord":{"modifiers":[]}}"#.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ShortcutBinding.self, from: data)
        }
    }
}
