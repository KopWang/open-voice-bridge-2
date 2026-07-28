import CoreGraphics
import Testing
@testable import XiaomiRemoteBridgeMac

@Suite("Shortcut capture event tap")
struct ShortcutCaptureEventTapTests {
    @Test func capturesAtTheHIDLayerBeforeMissionControl() {
        #expect(
            ShortcutCaptureEventTap.location.rawValue ==
                CGEventTapLocation.cghidEventTap.rawValue
        )
    }

    @Test func physicalShortcutEventsAreCapturedAndSuppressed() {
        for type in [
            CGEventType.flagsChanged,
            .keyDown,
            .keyUp,
        ] {
            #expect(
                ShortcutCaptureEventPolicy.disposition(
                    type: type,
                    isSynthetic: false
                ) == .captureAndSuppress
            )
        }
    }

    @Test func syntheticEventsPassThrough() {
        #expect(
            ShortcutCaptureEventPolicy.disposition(
                type: .keyDown,
                isSynthetic: true
            ) == .passThrough
        )
    }

    @Test func disabledTapEventsAreReenabledAndPassedThrough() {
        for type in [
            CGEventType.tapDisabledByTimeout,
            .tapDisabledByUserInput,
        ] {
            #expect(
                ShortcutCaptureEventPolicy.disposition(
                    type: type,
                    isSynthetic: false
                ) == .reenableAndPassThrough
            )
        }
    }

    @Test func unrelatedEventsPassThrough() {
        #expect(
            ShortcutCaptureEventPolicy.disposition(
                type: .mouseMoved,
                isSynthetic: false
            ) == .passThrough
        )
    }
}
