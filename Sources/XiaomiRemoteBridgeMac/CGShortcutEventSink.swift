import CoreGraphics
import Foundation

final class CGShortcutEventSink: ShortcutEventSink {
    func post(_ event: ShortcutEvent) -> Bool {
        guard KeyboardInjector.isAccessibilityTrusted else { return false }

        switch event {
        case let .modifier(modifier, isDown, activeModifiers):
            return postKey(
                code: modifier.virtualKeyCode,
                isDown: isDown,
                activeModifiers: activeModifiers
            )
        case let .key(key, isDown, activeModifiers):
            return postKey(
                code: CGKeyCode(key.keyCode),
                isDown: isDown,
                activeModifiers: activeModifiers
            )
        case let .system(action):
            return KeyboardInjector.send(action)
        }
    }

    private func postKey(
        code: CGKeyCode,
        isDown: Bool,
        activeModifiers: Set<KeyModifier>
    ) -> Bool {
        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: code,
                keyDown: isDown
            )
        else {
            return false
        }
        event.flags = activeModifiers.cgEventFlags
        event.setIntegerValueField(
            .eventSourceUserData,
            value: KeyboardInjector.syntheticEventMarker
        )
        event.post(tap: .cghidEventTap)
        return true
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
