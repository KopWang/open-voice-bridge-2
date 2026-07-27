import Foundation

enum ShortcutEvent: Equatable {
    case modifier(
        KeyModifier,
        isDown: Bool,
        activeModifiers: Set<KeyModifier>
    )
    case key(
        ShortcutKey,
        isDown: Bool,
        activeModifiers: Set<KeyModifier>
    )
    case system(SystemAction)
}

protocol ShortcutEventSink: AnyObject {
    func post(_ event: ShortcutEvent) -> Bool
}

final class ShortcutEmitter {
    private let sink: ShortcutEventSink
    private var activeButtons = Set<RemoteButton>()
    private var heldChords: [RemoteButton: KeyChord] = [:]

    init(sink: ShortcutEventSink) {
        self.sink = sink
    }

    @discardableResult
    func handle(
        _ edge: RemoteEventEdge,
        button: RemoteButton,
        binding: ShortcutBinding
    ) -> Bool {
        switch edge {
        case .down:
            guard activeButtons.insert(button).inserted else { return true }
            switch binding {
            case .disabled:
                return true
            case let .system(action):
                guard sink.post(.system(action)) else {
                    activeButtons.remove(button)
                    return false
                }
                return true
            case let .chord(chord):
                guard press(chord) else {
                    activeButtons.remove(button)
                    return false
                }
                heldChords[button] = chord
                return true
            }

        case .up:
            guard activeButtons.remove(button) != nil else { return true }
            guard let chord = heldChords.removeValue(forKey: button) else { return true }
            return release(chord)
        }
    }

    @discardableResult
    func replaceBinding(for button: RemoteButton) -> Bool {
        activeButtons.remove(button)
        guard let chord = heldChords.removeValue(forKey: button) else { return true }
        return release(chord)
    }

    @discardableResult
    func forceReleaseAll(reason: String) -> Bool {
        _ = reason
        var succeeded = true
        for button in RemoteButton.allCases {
            guard let chord = heldChords.removeValue(forKey: button) else { continue }
            if !release(chord) { succeeded = false }
        }
        activeButtons.removeAll()
        return succeeded
    }

    private func press(_ chord: KeyChord) -> Bool {
        var activeModifiers = Set<KeyModifier>()
        var pressedModifiers: [KeyModifier] = []

        for modifier in chord.modifiers.sorted() {
            activeModifiers.insert(modifier)
            guard sink.post(.modifier(
                modifier,
                isDown: true,
                activeModifiers: activeModifiers
            )) else {
                activeModifiers.remove(modifier)
                rollback(pressedModifiers, activeModifiers: activeModifiers)
                return false
            }
            pressedModifiers.append(modifier)
        }

        if let key = chord.key {
            guard sink.post(.key(
                key,
                isDown: true,
                activeModifiers: activeModifiers
            )) else {
                rollback(pressedModifiers, activeModifiers: activeModifiers)
                return false
            }
        }
        return true
    }

    private func release(_ chord: KeyChord) -> Bool {
        var succeeded = true
        var activeModifiers = chord.modifiers

        if let key = chord.key,
           !sink.post(.key(key, isDown: false, activeModifiers: activeModifiers))
        {
            succeeded = false
        }

        for modifier in chord.modifiers.sorted().reversed() {
            activeModifiers.remove(modifier)
            if !sink.post(.modifier(
                modifier,
                isDown: false,
                activeModifiers: activeModifiers
            )) {
                succeeded = false
            }
        }
        return succeeded
    }

    private func rollback(
        _ pressedModifiers: [KeyModifier],
        activeModifiers: Set<KeyModifier>
    ) {
        var remaining = activeModifiers
        for modifier in pressedModifiers.reversed() {
            remaining.remove(modifier)
            _ = sink.post(.modifier(
                modifier,
                isDown: false,
                activeModifiers: remaining
            ))
        }
    }
}
