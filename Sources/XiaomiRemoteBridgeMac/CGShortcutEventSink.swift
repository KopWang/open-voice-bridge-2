import CoreGraphics
import Foundation

final class CGShortcutEventSink: ShortcutEventSink {
    func post(_ event: ShortcutEvent) -> Bool {
        guard KeyboardInjector.isAccessibilityTrusted else { return false }

        switch event {
        case let .system(action):
            return KeyboardInjector.send(action)
        case .modifier, .key:
            guard
                let source = CGEventSource(stateID: .hidSystemState),
                let keyboardEvent = Self.makeKeyboardEvent(
                    for: event,
                    source: source
                )
            else {
                return false
            }
            keyboardEvent.post(tap: .cghidEventTap)
            return true
        }
    }

    static func makeKeyboardEvent(
        for shortcutEvent: ShortcutEvent,
        source: CGEventSource
    ) -> CGEvent? {
        let code: CGKeyCode
        let isDown: Bool
        let activeModifiers: Set<KeyModifier>
        let isModifier: Bool

        switch shortcutEvent {
        case let .modifier(modifier, modifierIsDown, modifiers):
            code = modifier.virtualKeyCode
            isDown = modifierIsDown
            activeModifiers = modifiers
            isModifier = true
        case let .key(key, keyIsDown, modifiers):
            code = CGKeyCode(key.keyCode)
            isDown = keyIsDown
            activeModifiers = modifiers
            isModifier = false
        case .system:
            return nil
        }

        guard let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: code,
            keyDown: isDown
        ) else { return nil }
        if isModifier {
            event.type = .flagsChanged
        }
        event.flags = activeModifiers.cgEventFlags
        event.setIntegerValueField(
            .eventSourceUserData,
            value: KeyboardInjector.syntheticEventMarker
        )
        return event
    }
}

private extension KeyModifier {
    var virtualKeyCode: CGKeyCode {
        switch self {
        case .control: return 59
        case .option: return 58
        case .shift: return 56
        case .command: return 55
        }
    }
}

private extension Set where Element == KeyModifier {
    var cgEventFlags: CGEventFlags {
        reduce(into: CGEventFlags()) { flags, modifier in
            switch modifier {
            case .control: flags.insert(.maskControl)
            case .option: flags.insert(.maskAlternate)
            case .shift: flags.insert(.maskShift)
            case .command: flags.insert(.maskCommand)
            }
        }
    }
}
