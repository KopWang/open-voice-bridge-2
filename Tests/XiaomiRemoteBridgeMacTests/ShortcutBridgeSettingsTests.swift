import Foundation
import Testing
@testable import XiaomiRemoteBridgeMac

@Suite("Shortcut bridge settings")
struct ShortcutBridgeSettingsTests {
    @Test func defaultsCoverEveryButtonAndVoiceUsesControlOption() throws {
        let expectedVoice = try #require(
            KeyChord(modifiers: [.control, .option], key: nil)
        )
        let expectedMenu = try #require(
            KeyChord(modifiers: [.control], key: nil)
        )

        #expect(ShortcutBridgeSettings.defaultBindings.count == 13)
        #expect(
            ShortcutBridgeSettings.defaultBindings[.microphone] == .chord(expectedVoice)
        )
        #expect(
            ShortcutBridgeSettings.defaultBindings[.menu] == .chord(expectedMenu)
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

    @Test func migratesUntouchedLegacyMenuDefaultToControl() throws {
        let suiteName = "RemoteShortcutBridgeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        try save(
            [.menu: .system(.contextMenu)],
            to: defaults
        )

        let settings = ShortcutBridgeSettings(defaults: defaults)
        let control = try #require(
            KeyChord(modifiers: [.control], key: nil)
        )
        #expect(settings.binding(for: .menu) == .chord(control))
        #expect(defaults.integer(forKey: "shortcutMappingSchemaVersion") == 2)
    }

    @Test func migrationPreservesCustomMenuBinding() throws {
        let suiteName = "RemoteShortcutBridgeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        try save([.menu: .disabled], to: defaults)

        let settings = ShortcutBridgeSettings(defaults: defaults)
        #expect(settings.binding(for: .menu) == .disabled)
        #expect(defaults.integer(forKey: "shortcutMappingSchemaVersion") == 2)
    }

    private func save(
        _ bindings: [RemoteButton: ShortcutBinding],
        to defaults: UserDefaults
    ) throws {
        let raw = Dictionary(
            uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) }
        )
        defaults.set(
            try JSONEncoder().encode(raw),
            forKey: "shortcutBindings"
        )
    }
}
