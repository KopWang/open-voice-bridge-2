import Foundation
import Testing
@testable import XiaomiRemoteBridgeMac

@Suite("Shortcut bridge settings")
struct ShortcutBridgeSettingsTests {
    @Test func defaultsCoverEveryButtonAndVoiceUsesControlOption() throws {
        let expectedVoice = try #require(
            KeyChord(modifiers: [.control, .option], key: nil)
        )

        #expect(ShortcutBridgeSettings.defaultBindings.count == 13)
        #expect(
            ShortcutBridgeSettings.defaultBindings[.microphone] == .chord(expectedVoice)
        )
        for button in RemoteButton.allCases {
            #expect(ShortcutBridgeSettings.defaultBindings[button] != nil)
        }
    }

    @Test func savedBindingsPersistAndMergeWithDefaults() throws {
        let suiteName = "RemoteShortcutBridgeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = ShortcutBridgeSettings(defaults: defaults)
        settings.setBinding(.disabled, for: .microphone)

        let reloaded = ShortcutBridgeSettings(defaults: defaults)
        #expect(reloaded.binding(for: .microphone) == .disabled)
        #expect(reloaded.binding(for: .up) == ShortcutBridgeSettings.defaultBindings[.up])
    }

    @Test func launchAtLoginDefaultsOnAndPersistsOptOut() throws {
        let suiteName = "RemoteShortcutBridgeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = ShortcutBridgeSettings(defaults: defaults)
        #expect(settings.launchAtLoginEnabled)
        settings.launchAtLoginEnabled = false

        #expect(!ShortcutBridgeSettings(defaults: defaults).launchAtLoginEnabled)
    }
}
