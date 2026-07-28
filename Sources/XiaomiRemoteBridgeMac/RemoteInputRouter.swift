import Foundation

final class RemoteInputRouter {
    private struct ActiveCombination {
        let chord: RemoteButtonChord
        let binding: ShortcutBinding
    }

    private let settings: ShortcutBridgeSettings
    private let emitter: ShortcutEmitter
    private let scheduler: ShortcutPulseScheduling
    private let combinationWindow: TimeInterval

    private var physicalPressed = Set<RemoteButton>()
    private var pendingSingles: [RemoteButton: UInt64] = [:]
    private var emittedSingles = Set<RemoteButton>()
    private var consumedButtons = Set<RemoteButton>()
    private var activeCombination: ActiveCombination?
    private var nextToken: UInt64 = 0

    init(
        settings: ShortcutBridgeSettings,
        emitter: ShortcutEmitter,
        scheduler: ShortcutPulseScheduling = DispatchShortcutPulseScheduler(),
        combinationWindow: TimeInterval = 0.14
    ) {
        self.settings = settings
        self.emitter = emitter
        self.scheduler = scheduler
        self.combinationWindow = combinationWindow
    }

    @discardableResult
    func update(pressed: Set<RemoteButton>) -> Bool {
        let released = physicalPressed.subtracting(pressed)
        let added = pressed.subtracting(physicalPressed)
        physicalPressed = pressed
        var succeeded = true

        if
            let activeCombination,
            !activeCombination.chord.buttons.isSubset(of: pressed)
        {
            if !emitter.handle(
                .up,
                button: activeCombination.chord.owner,
                binding: activeCombination.binding
            ) {
                succeeded = false
            }
            self.activeCombination = nil
        }

        for button in ordered(released) {
            if !releaseSingle(button) {
                succeeded = false
            }
        }
        for button in ordered(added) {
            if !pressSingleOrDefer(button) {
                succeeded = false
            }
        }
        if activeCombination == nil, !startMatchingCombination() {
            succeeded = false
        }

        if consumedButtons.isDisjoint(with: physicalPressed) {
            consumedButtons.removeAll()
        }
        return succeeded
    }

    @discardableResult
    func forceReleaseAll(reason: String) -> Bool {
        physicalPressed.removeAll()
        pendingSingles.removeAll()
        emittedSingles.removeAll()
        consumedButtons.removeAll()
        activeCombination = nil
        return emitter.forceReleaseAll(reason: reason)
    }

    private func pressSingleOrDefer(_ button: RemoteButton) -> Bool {
        guard !consumedButtons.contains(button) else { return true }
        if participatesInCombination(button) {
            nextToken &+= 1
            let token = nextToken
            pendingSingles[button] = token
            scheduler.schedule(after: combinationWindow) { [weak self] in
                self?.settleSingle(button, token: token)
            }
            return true
        }

        let succeeded = emitter.handle(
            .down,
            button: button,
            binding: settings.binding(for: button)
        )
        if succeeded {
            emittedSingles.insert(button)
        }
        return succeeded
    }

    private func releaseSingle(_ button: RemoteButton) -> Bool {
        if consumedButtons.contains(button) {
            pendingSingles.removeValue(forKey: button)
            emittedSingles.remove(button)
            return true
        }

        if pendingSingles.removeValue(forKey: button) != nil {
            let binding = settings.binding(for: button)
            guard emitter.handle(.down, button: button, binding: binding) else {
                return false
            }
            return emitter.handle(.up, button: button, binding: binding)
        }

        guard emittedSingles.remove(button) != nil else { return true }
        return emitter.handle(
            .up,
            button: button,
            binding: settings.binding(for: button)
        )
    }

    private func settleSingle(_ button: RemoteButton, token: UInt64) {
        guard
            pendingSingles[button] == token,
            physicalPressed.contains(button),
            !consumedButtons.contains(button),
            activeCombination == nil
        else {
            return
        }
        pendingSingles.removeValue(forKey: button)
        if emitter.handle(
            .down,
            button: button,
            binding: settings.binding(for: button)
        ) {
            emittedSingles.insert(button)
        }
    }

    private func startMatchingCombination() -> Bool {
        let candidates = settings.combinationBindings.keys
            .filter { chord in
                chord.buttons.isSubset(of: physicalPressed) &&
                    chord.buttons.allSatisfy {
                        pendingSingles[$0] != nil
                    }
            }
            .sorted {
                if $0.buttons.count != $1.buttons.count {
                    return $0.buttons.count > $1.buttons.count
                }
                return $0.id < $1.id
            }
        guard
            let chord = candidates.first,
            let binding = settings.combinationBinding(for: chord)
        else {
            return true
        }

        for button in chord.buttons {
            pendingSingles.removeValue(forKey: button)
        }
        consumedButtons.formUnion(chord.buttons)
        let succeeded = emitter.handle(
            .down,
            button: chord.owner,
            binding: binding
        )
        if succeeded {
            activeCombination = ActiveCombination(
                chord: chord,
                binding: binding
            )
        }
        return succeeded
    }

    private func participatesInCombination(_ button: RemoteButton) -> Bool {
        settings.combinationBindings.keys.contains {
            $0.buttons.contains(button)
        }
    }

    private func ordered(
        _ buttons: Set<RemoteButton>
    ) -> [RemoteButton] {
        RemoteButton.allCases.filter(buttons.contains)
    }
}
