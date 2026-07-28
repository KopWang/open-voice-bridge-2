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
    private let modifierReleaseGrace: TimeInterval

    private var physicalPressed = Set<RemoteButton>()
    private var pendingSingles: [RemoteButton: UInt64] = [:]
    private var pendingModifierReleases: [RemoteButton: UInt64] = [:]
    private var emittedSingles = Set<RemoteButton>()
    private var latchedModifiers = Set<RemoteButton>()
    private var modifiersUsedWithAnotherKey = Set<RemoteButton>()
    private var consumedButtons = Set<RemoteButton>()
    private var activeCombination: ActiveCombination?
    private var nextToken: UInt64 = 0

    init(
        settings: ShortcutBridgeSettings,
        emitter: ShortcutEmitter,
        scheduler: ShortcutPulseScheduling = DispatchShortcutPulseScheduler(),
        combinationWindow: TimeInterval = 0.5,
        modifierReleaseGrace: TimeInterval = 0.5
    ) {
        self.settings = settings
        self.emitter = emitter
        self.scheduler = scheduler
        self.combinationWindow = combinationWindow
        self.modifierReleaseGrace = modifierReleaseGrace
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
        if !added.isEmpty {
            adoptPendingModifiers()
            markPhysicalModifiersUsed(with: added)
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
        if physicalPressed.isEmpty, !releaseLatchedModifiers() {
            succeeded = false
        }
        return succeeded
    }

    @discardableResult
    func forceReleaseAll(reason: String) -> Bool {
        physicalPressed.removeAll()
        pendingSingles.removeAll()
        pendingModifierReleases.removeAll()
        emittedSingles.removeAll()
        latchedModifiers.removeAll()
        modifiersUsedWithAnotherKey.removeAll()
        consumedButtons.removeAll()
        activeCombination = nil
        return emitter.forceReleaseAll(reason: reason)
    }

    func shouldSuppressNativeEvent(for button: RemoteButton) -> Bool {
        if !settings.binding(for: button).isDisabled {
            return true
        }
        return settings.combinationBindings.contains { chord, binding in
            !binding.isDisabled && chord.buttons.contains(button)
        }
    }

    private func pressSingleOrDefer(_ button: RemoteButton) -> Bool {
        guard !consumedButtons.contains(button) else { return true }
        if pendingModifierReleases.removeValue(forKey: button) != nil {
            latchedModifiers.remove(button)
            return true
        }
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

        if pendingSingles[button] != nil {
            return true
        }

        guard emittedSingles.contains(button) else { return true }
        let binding = settings.binding(for: button)
        if
            binding.isSingleModifier,
            modifiersUsedWithAnotherKey.remove(button) == nil
        {
            scheduleModifierRelease(button)
            return true
        }
        return releaseEmittedSingle(button, binding: binding)
    }

    private func settleSingle(_ button: RemoteButton, token: UInt64) {
        guard
            pendingSingles[button] == token,
            !consumedButtons.contains(button),
            activeCombination == nil
        else {
            return
        }
        pendingSingles.removeValue(forKey: button)
        let binding = settings.binding(for: button)
        if emitter.handle(
            .down,
            button: button,
            binding: binding
        ) {
            if physicalPressed.contains(button) {
                emittedSingles.insert(button)
            } else {
                _ = emitter.handle(.up, button: button, binding: binding)
            }
        }
    }

    private func scheduleModifierRelease(_ button: RemoteButton) {
        nextToken &+= 1
        let token = nextToken
        pendingModifierReleases[button] = token
        scheduler.schedule(after: modifierReleaseGrace) { [weak self] in
            self?.finishModifierRelease(button, token: token)
        }
    }

    private func finishModifierRelease(
        _ button: RemoteButton,
        token: UInt64
    ) {
        guard
            pendingModifierReleases[button] == token,
            !physicalPressed.contains(button),
            !latchedModifiers.contains(button)
        else {
            return
        }
        pendingModifierReleases.removeValue(forKey: button)
        _ = releaseEmittedSingle(
            button,
            binding: settings.binding(for: button)
        )
    }

    private func adoptPendingModifiers() {
        for button in Array(pendingModifierReleases.keys) {
            pendingModifierReleases.removeValue(forKey: button)
            latchedModifiers.insert(button)
        }
    }

    private func markPhysicalModifiersUsed(
        with added: Set<RemoteButton>
    ) {
        guard !added.isEmpty else { return }
        for button in physicalPressed.subtracting(added) {
            if
                emittedSingles.contains(button),
                settings.binding(for: button).isSingleModifier
            {
                modifiersUsedWithAnotherKey.insert(button)
            }
        }
    }

    private func releaseLatchedModifiers() -> Bool {
        var succeeded = true
        for button in ordered(latchedModifiers) {
            if !releaseEmittedSingle(
                button,
                binding: settings.binding(for: button)
            ) {
                succeeded = false
            }
        }
        latchedModifiers.removeAll()
        return succeeded
    }

    private func releaseEmittedSingle(
        _ button: RemoteButton,
        binding: ShortcutBinding
    ) -> Bool {
        pendingModifierReleases.removeValue(forKey: button)
        modifiersUsedWithAnotherKey.remove(button)
        guard emittedSingles.remove(button) != nil else { return true }
        return emitter.handle(.up, button: button, binding: binding)
    }

    private func startMatchingCombination() -> Bool {
        let eligibleButtons = physicalPressed.union(pendingSingles.keys)
        let candidates = settings.combinationBindings.keys
            .filter { chord in
                chord.buttons.isSubset(of: eligibleButtons) &&
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

private extension ShortcutBinding {
    var isDisabled: Bool {
        if case .disabled = self { return true }
        return false
    }

    var isSingleModifier: Bool {
        guard case let .chord(chord) = self else { return false }
        return chord.key == nil && chord.modifiers.count == 1
    }
}
