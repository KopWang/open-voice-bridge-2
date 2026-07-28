import Foundation

protocol ShortcutPulseScheduling {
    func schedule(
        after delay: TimeInterval,
        _ action: @escaping () -> Void
    )
}

struct DispatchShortcutPulseScheduler: ShortcutPulseScheduling {
    func schedule(
        after delay: TimeInterval,
        _ action: @escaping () -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            action()
        }
    }
}

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
    private let scheduler: ShortcutPulseScheduling
    private let modifierPulseDuration: TimeInterval
    private var activeButtons = Set<RemoteButton>()
    private var heldChords: [RemoteButton: KeyChord] = [:]
    private var modifierOwners: [KeyModifier: Set<RemoteButton>] = [:]
    private var keyOwners: [ShortcutKey: Set<RemoteButton>] = [:]
    private var pulseTokens: [RemoteButton: UInt64] = [:]
    private var nextPulseToken: UInt64 = 0

    init(
        sink: ShortcutEventSink,
        scheduler: ShortcutPulseScheduling = DispatchShortcutPulseScheduler(),
        modifierPulseDuration: TimeInterval = 0.25
    ) {
        self.sink = sink
        self.scheduler = scheduler
        self.modifierPulseDuration = modifierPulseDuration
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
                guard press(chord, owner: button) else {
                    activeButtons.remove(button)
                    return false
                }
                heldChords[button] = chord
                if chord.isModifierShortcutPulse {
                    schedulePulseRelease(for: button)
                }
                return true
            }

        case .up:
            if pulseTokens[button] != nil {
                return true
            }
            guard activeButtons.remove(button) != nil else { return true }
            guard let chord = heldChords.removeValue(forKey: button) else { return true }
            return release(chord, owner: button)
        }
    }

    @discardableResult
    func replaceBinding(for button: RemoteButton) -> Bool {
        pulseTokens.removeValue(forKey: button)
        activeButtons.remove(button)
        guard let chord = heldChords.removeValue(forKey: button) else { return true }
        return release(chord, owner: button)
    }

    @discardableResult
    func forceReleaseAll(reason: String) -> Bool {
        _ = reason
        pulseTokens.removeAll()
        var succeeded = true
        for button in RemoteButton.allCases {
            guard let chord = heldChords.removeValue(forKey: button) else { continue }
            if !release(chord, owner: button) { succeeded = false }
        }
        activeButtons.removeAll()
        return succeeded
    }

    private func press(_ chord: KeyChord, owner: RemoteButton) -> Bool {
        var addedModifiers: [KeyModifier] = []
        for modifier in chord.modifiers.sorted() {
            var owners = modifierOwners[modifier] ?? []
            let wasHeld = !owners.isEmpty
            owners.insert(owner)
            modifierOwners[modifier] = owners
            addedModifiers.append(modifier)

            if !wasHeld,
               !sink.post(.modifier(
                   modifier,
                   isDown: true,
                   activeModifiers: activeModifiers
               ))
            {
                removeModifierOwner(
                    modifier,
                    owner: owner,
                    emitRelease: false
                )
                addedModifiers.removeLast()
                rollback(addedModifiers, owner: owner)
                return false
            }
        }

        if let key = chord.key {
            var owners = keyOwners[key] ?? []
            let wasHeld = !owners.isEmpty
            owners.insert(owner)
            keyOwners[key] = owners
            if !wasHeld,
               !sink.post(.key(
                   key,
                   isDown: true,
                   activeModifiers: activeModifiers
               ))
            {
                removeKeyOwner(key, owner: owner, emitRelease: false)
                rollback(addedModifiers, owner: owner)
                return false
            }
        }
        return true
    }

    private func release(_ chord: KeyChord, owner: RemoteButton) -> Bool {
        var succeeded = true

        if let key = chord.key {
            if !removeKeyOwner(key, owner: owner, emitRelease: true) {
                succeeded = false
            }
        }

        for modifier in chord.modifiers.sorted().reversed() {
            if !removeModifierOwner(
                modifier,
                owner: owner,
                emitRelease: true
            ) {
                succeeded = false
            }
        }
        return succeeded
    }

    private func rollback(
        _ modifiers: [KeyModifier],
        owner: RemoteButton
    ) {
        for modifier in modifiers.reversed() {
            _ = removeModifierOwner(
                modifier,
                owner: owner,
                emitRelease: true
            )
        }
    }

    private var activeModifiers: Set<KeyModifier> {
        Set(modifierOwners.compactMap { modifier, owners in
            owners.isEmpty ? nil : modifier
        })
    }

    @discardableResult
    private func removeModifierOwner(
        _ modifier: KeyModifier,
        owner: RemoteButton,
        emitRelease: Bool
    ) -> Bool {
        guard var owners = modifierOwners[modifier] else { return true }
        owners.remove(owner)
        guard owners.isEmpty else {
            modifierOwners[modifier] = owners
            return true
        }

        modifierOwners.removeValue(forKey: modifier)
        guard emitRelease else { return true }
        return sink.post(.modifier(
            modifier,
            isDown: false,
            activeModifiers: activeModifiers
        ))
    }

    @discardableResult
    private func removeKeyOwner(
        _ key: ShortcutKey,
        owner: RemoteButton,
        emitRelease: Bool
    ) -> Bool {
        guard var owners = keyOwners[key] else { return true }
        owners.remove(owner)
        guard owners.isEmpty else {
            keyOwners[key] = owners
            return true
        }

        keyOwners.removeValue(forKey: key)
        guard emitRelease else { return true }
        return sink.post(.key(
            key,
            isDown: false,
            activeModifiers: activeModifiers
        ))
    }

    private func schedulePulseRelease(for button: RemoteButton) {
        nextPulseToken &+= 1
        let token = nextPulseToken
        pulseTokens[button] = token
        scheduler.schedule(after: modifierPulseDuration) { [weak self] in
            self?.finishPulse(for: button, token: token)
        }
    }

    private func finishPulse(for button: RemoteButton, token: UInt64) {
        guard pulseTokens[button] == token else { return }
        pulseTokens.removeValue(forKey: button)
        activeButtons.remove(button)
        guard let chord = heldChords.removeValue(forKey: button) else { return }
        _ = release(chord, owner: button)
    }
}

private extension KeyChord {
    var isModifierShortcutPulse: Bool {
        key == nil && modifiers.count >= 2
    }
}
