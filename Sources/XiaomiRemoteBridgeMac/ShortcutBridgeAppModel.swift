import AppKit
import Combine
import Foundation

@MainActor
final class ShortcutBridgeAppModel: ObservableObject {
    let settings: ShortcutBridgeSettings
    let launchAtLoginManager: LaunchAtLoginManager

    @Published private(set) var hidStatus = "正在初始化"
    @Published private(set) var isConnected = false
    @Published private(set) var inputMonitoringGranted = false
    @Published private(set) var accessibilityGranted = false

    private let runtime: ShortcutBridgeRuntime
    private var started = false

    init(
        settings: ShortcutBridgeSettings = ShortcutBridgeSettings(),
        launchAtLoginManager: LaunchAtLoginManager = .shared
    ) {
        self.settings = settings
        self.launchAtLoginManager = launchAtLoginManager
        runtime = ShortcutBridgeRuntime(settings: settings)

        runtime.onStatus = { [weak self] status in
            self?.hidStatus = status
        }
        runtime.onConnectionChange = { [weak self] connected in
            self?.isConnected = connected
        }
        refreshPermissionState()
    }

    var permissionsReady: Bool {
        inputMonitoringGranted && accessibilityGranted
    }

    var versionText: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.1.0"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "1"
        return "\(version) (\(build))"
    }

    func startIfNeeded() {
        guard !started else { return }
        started = true
        refreshPermissionState()
        requestNextPermissionIfNeeded()
        runtime.start()
        hidStatus = runtime.status
        isConnected = runtime.isConnected
        AppLogger.shared.write("APP START controller_only=true")
    }

    func stop() {
        guard started else { return }
        started = false
        runtime.stop()
        isConnected = false
        AppLogger.shared.write("APP STOP")
    }

    func refresh() {
        refreshPermissionState()
        requestNextPermissionIfNeeded()
        guard started else {
            startIfNeeded()
            return
        }
        runtime.refresh()
        hidStatus = runtime.status
        isConnected = runtime.isConnected
    }

    func refreshAfterSystemSettings() {
        let wasReady = permissionsReady
        refreshPermissionState()
        requestNextPermissionIfNeeded()
        launchAtLoginManager.refreshStatus()

        guard started else { return }
        if permissionsReady && !wasReady {
            runtime.refresh()
            hidStatus = runtime.status
        } else if !permissionsReady {
            runtime.refresh()
            hidStatus = runtime.status
        }
    }

    func setBinding(_ binding: ShortcutBinding, for button: RemoteButton) {
        runtime.setBinding(binding, for: button)
    }

    func restoreDefaultBindings() {
        runtime.resetBindings()
    }

    func reconcileLaunchAtLogin() {
        launchAtLoginManager.apply(
            desiredEnabled: settings.launchAtLoginEnabled
        )
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        settings.launchAtLoginEnabled = enabled
        launchAtLoginManager.apply(desiredEnabled: enabled)
    }

    func requestInputMonitoringPermission() {
        _ = ShortcutHIDMonitor.requestInputMonitoringAccess()
        openPrivacyPane("Privacy_ListenEvent")
    }

    func requestAccessibilityPermission() {
        _ = KeyboardInjector.requestAccessibilityAccess()
        openPrivacyPane("Privacy_Accessibility")
    }

    func openLoginItemsSettings() {
        launchAtLoginManager.openLoginItemsSettings()
    }

    func openLogFolder() {
        AppLogger.shared.write("APP OPEN_LOG")
        NSWorkspace.shared.activateFileViewerSelecting([
            AppLogger.shared.logURL,
        ])
    }

    private func refreshPermissionState() {
        inputMonitoringGranted = ShortcutHIDMonitor.isInputMonitoringGranted
        accessibilityGranted = KeyboardInjector.isAccessibilityTrusted
    }

    private func requestNextPermissionIfNeeded() {
        if !inputMonitoringGranted {
            _ = ShortcutHIDMonitor.requestInputMonitoringAccess()
        } else if !accessibilityGranted {
            _ = KeyboardInjector.requestAccessibilityAccess()
        }
    }

    private func openPrivacyPane(_ pane: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
