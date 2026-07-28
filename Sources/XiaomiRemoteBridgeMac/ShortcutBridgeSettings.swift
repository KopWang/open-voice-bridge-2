import Combine
import Foundation

final class ShortcutBridgeSettings: ObservableObject {
    private enum Keys {
        static let bindings = "shortcutBindings"
        static let launchAtLoginEnabled = "launchAtLoginEnabled"
        static let mappingSchemaVersion = "shortcutMappingSchemaVersion"
    }

    private static let currentMappingSchemaVersion = 2
    private let defaults: UserDefaults

    @Published private(set) var bindings: [RemoteButton: ShortcutBinding] {
        didSet { saveBindings() }
    }

    @Published var launchAtLoginEnabled: Bool {
        didSet { defaults.set(launchAtLoginEnabled, forKey: Keys.launchAtLoginEnabled) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        launchAtLoginEnabled = defaults.object(forKey: Keys.launchAtLoginEnabled) == nil
            ? true
            : defaults.bool(forKey: Keys.launchAtLoginEnabled)

        var loadedBindings: [RemoteButton: ShortcutBinding]
        var savedBindings: [RemoteButton: ShortcutBinding] = [:]
        if
            let data = defaults.data(forKey: Keys.bindings),
            let decoded = try? JSONDecoder().decode([String: ShortcutBinding].self, from: data)
        {
            savedBindings = Dictionary(uniqueKeysWithValues: decoded.compactMap { rawButton, binding in
                RemoteButton(rawValue: rawButton).map { ($0, binding) }
            })
            loadedBindings = Self.defaultBindings.merging(savedBindings) { _, savedValue in savedValue }
        } else {
            loadedBindings = Self.defaultBindings
        }

        let schemaVersion = defaults.integer(forKey: Keys.mappingSchemaVersion)
        if
            schemaVersion < Self.currentMappingSchemaVersion,
            savedBindings[.menu] == .system(.contextMenu)
        {
            loadedBindings[.menu] = Self.defaultBindings[.menu]
        }
        bindings = loadedBindings

        saveBindings()
        defaults.set(
            Self.currentMappingSchemaVersion,
            forKey: Keys.mappingSchemaVersion
        )
    }

    func binding(for button: RemoteButton) -> ShortcutBinding {
        bindings[button] ?? .disabled
    }

    func setBinding(_ binding: ShortcutBinding, for button: RemoteButton) {
        bindings[button] = binding
    }

    func resetBindings() {
        bindings = Self.defaultBindings
    }

    private func saveBindings() {
        let raw = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: Keys.bindings)
        }
    }

    private static func chord(
        _ modifiers: Set<KeyModifier> = [],
        keyCode: UInt16? = nil,
        label: String = ""
    ) -> ShortcutBinding {
        let key = keyCode.map { ShortcutKey(keyCode: $0, displayName: label) }
        return .chord(KeyChord(modifiers: modifiers, key: key)!)
    }

    static let defaultBindings: [RemoteButton: ShortcutBinding] = [
        .microphone: chord([.control, .option]),
        .power: chord(keyCode: 53, label: "Escape"),
        .up: chord(keyCode: 126, label: "Up Arrow"),
        .left: chord(keyCode: 123, label: "Left Arrow"),
        .ok: chord(keyCode: 36, label: "Return"),
        .right: chord(keyCode: 124, label: "Right Arrow"),
        .down: chord(keyCode: 125, label: "Down Arrow"),
        .back: chord(keyCode: 51, label: "Delete"),
        .volumeUp: .system(.volumeUp),
        .home: .system(.showDesktop),
        .volumeDown: .system(.volumeDown),
        .menu: chord([.control]),
        .tv: chord([.command], keyCode: 48, label: "Tab"),
    ]
}
