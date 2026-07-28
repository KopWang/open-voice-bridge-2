import Foundation

struct RemoteButtonChord: Hashable, Codable, Identifiable {
    let buttons: Set<RemoteButton>

    init?(buttons: Set<RemoteButton>) {
        guard buttons.count >= 2 else { return nil }
        self.buttons = buttons
    }

    var id: String {
        orderedButtons.map(\.rawValue).joined(separator: "+")
    }

    var displayName: String {
        orderedButtons.map(\.shortLabel).joined(separator: " + ")
    }

    var owner: RemoteButton {
        orderedButtons[0]
    }

    private var orderedButtons: [RemoteButton] {
        RemoteButton.allCases.filter(buttons.contains)
    }
}

struct RemoteComboMapping: Codable, Equatable {
    let chord: RemoteButtonChord
    let binding: ShortcutBinding
}
