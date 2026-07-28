import Foundation
import IOKit.hid

enum HIDManagerOpenMode: Equatable {
    case monitored
}

enum HIDManagerOpenPolicy {
    static let options = IOOptionBits(kIOHIDOptionsTypeNone)
    static let mode = HIDManagerOpenMode.monitored
}

enum HIDDeviceOpenPolicy {
    static let options = IOOptionBits(kIOHIDOptionsTypeNone)
}

private func shortcutHIDDeviceMatched(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    let monitor = Unmanaged<ShortcutHIDMonitor>
        .fromOpaque(context)
        .takeUnretainedValue()
    monitor.deviceDidMatch(result: result, device: device)
}

private func shortcutHIDDeviceRemoved(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    let monitor = Unmanaged<ShortcutHIDMonitor>
        .fromOpaque(context)
        .takeUnretainedValue()
    monitor.deviceDidRemove(device: device)
}

private func shortcutHIDInputReport(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    type: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex
) {
    guard
        let context,
        result == kIOReturnSuccess,
        reportLength > 0
    else {
        return
    }
    let monitor = Unmanaged<ShortcutHIDMonitor>
        .fromOpaque(context)
        .takeUnretainedValue()
    guard let generation = monitor.currentReportGeneration else { return }
    let data = Data(bytes: report, count: reportLength)
    DispatchQueue.main.async {
        monitor.handleReport(
            reportID: reportID,
            data: data,
            generation: generation
        )
    }
}

final class ShortcutHIDMonitor {
    private let router: RemoteInputRouter
    private let eventSuppressor = KeyboardEventSuppressor()
    private var manager: IOHIDManager?
    private var lifecycle = RemoteDeviceLifecycle()
    private var activeDevice: IOHIDDevice?
    private var edgeTracker = RemoteButtonEdgeTracker()
    private var permissionMonitor: DispatchSourceTimer?

    private(set) var status = "等待遥控器"
    private(set) var isConnected = false
    private(set) var isExclusivelyReading = false

    var onStatus: ((String) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?

    fileprivate var currentReportGeneration: UInt64? {
        lifecycle.activeGeneration
    }

    static var isInputMonitoringGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    @discardableResult
    static func requestInputMonitoringAccess() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    init(router: RemoteInputRouter) {
        self.router = router
    }

    func start() {
        stop(reason: "restart")

        let inputGranted = Self.isInputMonitoringGranted
        let accessibilityGranted = KeyboardInjector.isAccessibilityTrusted
        AppLogger.shared.write(
            "HID PERMISSIONS input=\(inputGranted) accessibility=\(accessibilityGranted)"
        )
        guard inputGranted, accessibilityGranted else {
            updateStatus(
                inputGranted
                    ? "需要辅助功能权限"
                    : "需要输入监控权限"
            )
            return
        }

        let manager = IOHIDManagerCreate(
            kCFAllocatorDefault,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
        IOHIDManagerSetDeviceMatching(
            manager,
            [
                kIOHIDVendorIDKey as String: RC003ControllerIdentity.vendorID,
                kIOHIDProductIDKey as String: RC003ControllerIdentity.productID,
            ] as CFDictionary
        )

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(
            manager,
            shortcutHIDDeviceMatched,
            context
        )
        IOHIDManagerRegisterDeviceRemovalCallback(
            manager,
            shortcutHIDDeviceRemoved,
            context
        )
        IOHIDManagerRegisterInputReportCallback(
            manager,
            shortcutHIDInputReport,
            context
        )
        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )

        let result = IOHIDManagerOpen(manager, HIDManagerOpenPolicy.options)
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(
                manager,
                CFRunLoopGetMain(),
                CFRunLoopMode.commonModes.rawValue
            )
            eventSuppressor.stop()
            updateStatus("无法读取遥控器（错误 \(result)）")
            AppLogger.shared.write("HID START FAILED monitor=\(result)")
            return
        }

        let suppressionReady = eventSuppressor.start()
        AppLogger.shared.write(
            "HID FILTER active=\(eventSuppressor.isRunning) ready=\(suppressionReady)"
        )

        self.manager = manager
        lifecycle.openPipeline()
        startPermissionMonitor()
        updateStatus("等待 RC003 遥控器")
        AppLogger.shared.write("HID START mode=controller_only access=monitored")
    }

    func refresh() {
        start()
    }

    func stop(reason: String = "app_stop") {
        permissionMonitor?.cancel()
        permissionMonitor = nil
        _ = router.forceReleaseAll(reason: reason)
        edgeTracker.reset()
        eventSuppressor.stop()

        if let activeDevice {
            IOHIDDeviceClose(activeDevice, HIDDeviceOpenPolicy.options)
            self.activeDevice = nil
        }
        isExclusivelyReading = false

        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(
                manager,
                CFRunLoopGetMain(),
                CFRunLoopMode.commonModes.rawValue
            )
            IOHIDManagerClose(
                manager,
                IOOptionBits(kIOHIDOptionsTypeNone)
            )
            self.manager = nil
        }
        lifecycle.closePipeline()
        setConnected(false)
    }

    fileprivate func deviceDidMatch(result: IOReturn, device: IOHIDDevice) {
        guard manager != nil, !lifecycle.devicePresent else { return }

        let openResult = result == kIOReturnSuccess
            ? IOHIDDeviceOpen(device, HIDDeviceOpenPolicy.options)
            : result
        let openSucceeded = openResult == kIOReturnSuccess
        switch lifecycle.matched(openSucceeded: openSucceeded) {
        case .ignored:
            return
        case .unreadable:
            updateStatus("无法读取 RC003（错误 \(openResult)）")
            AppLogger.shared.write(
                "HID DEVICE OPEN FAILED result=\(openResult)"
            )
            DispatchQueue.main.async { [weak self] in
                self?.failReaderClosed(result: openResult)
            }
        case .present:
            activeDevice = device
            isExclusivelyReading = false
            edgeTracker.reset()
            _ = router.forceReleaseAll(reason: "device_generation_changed")
            setConnected(true)
            let detail = eventSuppressor.isRunning
                ? "键盘模式"
                : "键盘模式；系统原按键可能保留"
            updateStatus("RC003 已连接（\(detail)）")
            AppLogger.shared.write(
                "HID CONNECTED mode=monitored device_open=\(openResult)"
            )
        }
    }

    fileprivate func deviceDidRemove(device: IOHIDDevice) {
        guard let activeDevice, CFEqual(activeDevice, device) else { return }
        _ = lifecycle.removed()
        _ = router.forceReleaseAll(reason: "device_removed")
        edgeTracker.reset()
        IOHIDDeviceClose(activeDevice, HIDDeviceOpenPolicy.options)
        self.activeDevice = nil
        isExclusivelyReading = false
        setConnected(false)
        updateStatus("RC003 已断开；等待重新连接")
        AppLogger.shared.write("HID DISCONNECTED")
    }

    fileprivate func handleReport(
        reportID: UInt32,
        data: Data,
        generation: UInt64
    ) {
        guard manager != nil, lifecycle.accepts(generation: generation) else {
            return
        }
        guard runtimePermissionsAreValid() else {
            releaseForRevokedPermissions()
            return
        }
        guard let usages = RemoteHIDReportParser.usages(
            reportID: reportID,
            data: data
        ) else {
            return
        }

        let pressed = Set(usages.compactMap { RemoteButton.usageMap[$0] })
        let transitions = edgeTracker.update(usages: usages)
        AppLogger.shared.write(
            "HID REPORT " + HIDReportDiagnostics.describe(
                reportID: reportID,
                data: data,
                pressed: pressed
            )
        )
        for transition in transitions {
            eventSuppressor.arm(
                button: transition.button,
                edge: transition.edge
            )
            AppLogger.shared.write(
                "HID BUTTON edge=\(transition.edge) button=\(transition.button.rawValue)"
            )
        }
        guard router.update(pressed: pressed) else {
            releaseForRevokedPermissions()
            return
        }
    }

    private func startPermissionMonitor() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .seconds(1), repeating: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self, self.manager != nil else { return }
            if !self.runtimePermissionsAreValid() {
                self.releaseForRevokedPermissions()
            }
        }
        permissionMonitor = timer
        timer.resume()
    }

    private func runtimePermissionsAreValid() -> Bool {
        Self.isInputMonitoringGranted &&
            KeyboardInjector.isAccessibilityTrusted
    }

    private func releaseForRevokedPermissions() {
        stop(reason: "permission_revoked")
        updateStatus("系统权限已失效；已释放所有按键")
        AppLogger.shared.write("HID RELEASED permission_revoked")
    }

    private func failReaderClosed(result: IOReturn) {
        guard manager != nil, !lifecycle.devicePresent else { return }
        stop(reason: "device_open_failed")
        updateStatus("无法读取 RC003（错误 \(result)）")
    }

    private func updateStatus(_ value: String) {
        status = value
        onStatus?(value)
    }

    private func setConnected(_ value: Bool) {
        guard value != isConnected else { return }
        isConnected = value
        onConnectionChange?(value)
    }
}
