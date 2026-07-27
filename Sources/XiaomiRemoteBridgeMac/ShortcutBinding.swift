import Foundation

enum KeyModifier: String, CaseIterable, Codable, Hashable, Comparable {
    case control
    case option
    case shift
    case command

    private var sortOrder: Int {
        switch self {
        case .control: return 0
        case .option: return 1
        case .shift: return 2
        case .command: return 3
        }
    }

    static func < (lhs: KeyModifier, rhs: KeyModifier) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    var displayName: String {
        switch self {
        case .control: return "Control"
        case .option: return "Option"
        case .shift: return "Shift"
        case .command: return "Command"
        }
    }
}

struct ShortcutKey: Codable, Equatable, Hashable {
    let keyCode: UInt16
    let displayName: String

    init(keyCode: UInt16, displayName: String) {
        self.keyCode = keyCode
        let cleaned = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = cleaned.isEmpty ? "Key \(keyCode)" : cleaned
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode
        case displayName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            keyCode: try container.decode(UInt16.self, forKey: .keyCode),
            displayName: try container.decode(String.self, forKey: .displayName)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(displayName, forKey: .displayName)
    }
}

struct KeyChord: Codable, Equatable {
    let modifiers: Set<KeyModifier>
    let key: ShortcutKey?

    init?(modifiers: Set<KeyModifier>, key: ShortcutKey?) {
        guard !modifiers.isEmpty || key != nil else { return nil }
        self.modifiers = modifiers
        self.key = key
    }

    var displayName: String {
        (modifiers.sorted().map(\.displayName) + [key?.displayName].compactMap { $0 })
            .joined(separator: " + ")
    }

    private enum CodingKeys: String, CodingKey {
        case modifiers
        case key
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let modifiers = try container.decode(Set<KeyModifier>.self, forKey: .modifiers)
        let key = try container.decodeIfPresent(ShortcutKey.self, forKey: .key)
        guard let value = KeyChord(modifiers: modifiers, key: key) else {
            throw DecodingError.dataCorruptedError(
                forKey: .modifiers,
                in: container,
                debugDescription: "A shortcut chord cannot be empty"
            )
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modifiers, forKey: .modifiers)
        try container.encodeIfPresent(key, forKey: .key)
    }
}

enum SystemAction: String, CaseIterable, Codable, Equatable {
    case volumeUp
    case volumeDown
    case showDesktop
    case contextMenu

    var displayName: String {
        switch self {
        case .volumeUp: return "系统音量 +"
        case .volumeDown: return "系统音量 -"
        case .showDesktop: return "显示桌面"
        case .contextMenu: return "上下文菜单"
        }
    }
}

enum ShortcutBinding: Codable, Equatable {
    case disabled
    case chord(KeyChord)
    case system(SystemAction)

    private enum Kind: String, Codable {
        case disabled
        case chord
        case system
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case chord
        case system
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .disabled:
            self = .disabled
        case .chord:
            self = .chord(try container.decode(KeyChord.self, forKey: .chord))
        case .system:
            self = .system(try container.decode(SystemAction.self, forKey: .system))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .disabled:
            try container.encode(Kind.disabled, forKey: .kind)
        case let .chord(chord):
            try container.encode(Kind.chord, forKey: .kind)
            try container.encode(chord, forKey: .chord)
        case let .system(action):
            try container.encode(Kind.system, forKey: .kind)
            try container.encode(action, forKey: .system)
        }
    }

    var displayName: String {
        switch self {
        case .disabled: return "未设置"
        case let .chord(chord): return chord.displayName
        case let .system(action): return action.displayName
        }
    }
}
