import CoreGraphics
import Foundation

enum ShortcutCaptureEventDisposition: Equatable {
    case captureAndSuppress
    case passThrough
    case reenableAndPassThrough
}

enum ShortcutCaptureEventPolicy {
    static func disposition(
        type: CGEventType,
        isSynthetic: Bool
    ) -> ShortcutCaptureEventDisposition {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            return .reenableAndPassThrough
        }
        if isSynthetic {
            return .passThrough
        }
        switch type {
        case .flagsChanged, .keyDown, .keyUp:
            return .captureAndSuppress
        default:
            return .passThrough
        }
    }
}

private func shortcutCaptureEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<ShortcutCaptureEventTap>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    return monitor.handle(type: type, event: event)
}

final class ShortcutCaptureEventTap {
    typealias Handler = (CGEventType, CGEvent) -> Void
    static let location = CGEventTapLocation.cghidEventTap

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handler: Handler?

    private(set) var isRunning = false

    deinit {
        stop()
    }

    @discardableResult
    func start(handler: @escaping Handler) -> Bool {
        stop()

        let eventMask =
            CGEventMask(1 << CGEventType.flagsChanged.rawValue) |
            CGEventMask(1 << CGEventType.keyDown.rawValue) |
            CGEventMask(1 << CGEventType.keyUp.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let eventTap = CGEvent.tapCreate(
            tap: Self.location,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: shortcutCaptureEventTapCallback,
            userInfo: context
        ) else {
            return false
        }
        guard let runLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventTap,
            0
        ) else {
            CFMachPortInvalidate(eventTap)
            return false
        }

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        self.handler = handler
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            runLoopSource,
            .commonModes
        )
        CGEvent.tapEnable(tap: eventTap, enable: true)
        isRunning = true
        return true
    }

    func stop() {
        handler = nil
        if let runLoopSource {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                runLoopSource,
                .commonModes
            )
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
        isRunning = false
    }

    fileprivate func handle(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        let isSynthetic =
            event.getIntegerValueField(.eventSourceUserData) ==
            KeyboardInjector.syntheticEventMarker

        switch ShortcutCaptureEventPolicy.disposition(
            type: type,
            isSynthetic: isSynthetic
        ) {
        case .captureAndSuppress:
            handler?(type, event)
            return nil
        case .passThrough:
            return Unmanaged.passUnretained(event)
        case .reenableAndPassThrough:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
    }
}
