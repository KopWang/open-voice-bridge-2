import AppKit
import Combine
import Darwin
import SwiftUI

@main
enum XiaomiRemoteBridgeMacApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = RemoteShortcutBridgeAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
private final class RemoteShortcutBridgeAppDelegate:
    NSObject,
    NSApplicationDelegate,
    NSMenuDelegate,
    NSWindowDelegate
{
    private let model = ShortcutBridgeAppModel()
    private var statusItem: NSStatusItem?
    private var settingsWindowController: NSWindowController?
    private var subscriptions = Set<AnyCancellable>()
    private var terminationSignalSources: [DispatchSourceSignal] = []

    private let connectionItem = NSMenuItem(
        title: "正在初始化",
        action: nil,
        keyEquivalent: ""
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        installTerminationSignalHandlers()
        configureStatusItem()
        observeModel()
        model.reconcileLaunchAtLogin()
        model.startIfNeeded()
        refreshMenuStatus()

        let hasOpenedSettings = UserDefaults.standard.bool(
            forKey: "hasOpenedShortcutSettings"
        )
        if !hasOpenedSettings || !model.permissionsReady {
            showSettings()
            UserDefaults.standard.set(
                true,
                forKey: "hasOpenedShortcutSettings"
            )
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        settingsWindowController?.window?.contentViewController = nil
        settingsWindowController = nil
        model.stop()
        terminationSignalSources.forEach { $0.cancel() }
        terminationSignalSources.removeAll()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.refreshAfterSystemSettings()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showSettings()
        return true
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuStatus()
    }

    private func installTerminationSignalHandlers() {
        for signalNumber in [SIGTERM, SIGINT] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(
                signal: signalNumber,
                queue: .main
            )
            source.setEventHandler {
                NSApp.terminate(nil)
            }
            source.resume()
            terminationSignalSources.append(source)
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )
        if let button = item.button {
            button.toolTip = "遥控快捷桥"
            let image = NSImage(
                systemSymbolName: "keyboard",
                accessibilityDescription: "遥控快捷桥"
            )
            image?.isTemplate = true
            button.image = image
            if image == nil {
                button.title = "遥控"
            }
        }

        connectionItem.isEnabled = false

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(connectionItem)
        menu.addItem(.separator())
        menu.addItem(menuItem("重新连接", action: #selector(refresh)))
        menu.addItem(menuItem("打开设置…", action: #selector(showSettings)))
        menu.addItem(menuItem("显示日志", action: #selector(showLog)))
        menu.addItem(.separator())
        menu.addItem(menuItem("退出遥控快捷桥", action: #selector(quit)))
        item.menu = menu
        statusItem = item
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func observeModel() {
        model.$hidStatus
            .combineLatest(model.$isConnected)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshMenuStatus()
            }
            .store(in: &subscriptions)
    }

    private func refreshMenuStatus() {
        connectionItem.title = model.hidStatus
        let symbol = model.isConnected ? "keyboard.fill" : "keyboard"
        statusItem?.button?.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: model.isConnected
                ? "RC003 已连接"
                : "RC003 未连接"
        )
    }

    @objc private func refresh() {
        model.refresh()
    }

    @objc private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = makeSettingsWindowController()
        }
        guard
            let windowController = settingsWindowController,
            let window = windowController.window
        else {
            return
        }
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeSettingsWindowController() -> NSWindowController {
        let hostingController = NSHostingController(
            rootView: ShortcutSettingsView(model: model)
        )
        if #available(macOS 13.0, *) {
            hostingController.sizingOptions = []
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "遥控快捷桥"
        window.contentViewController = hostingController
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 620, height: 540)
        window.setFrameAutosaveName("RemoteShortcutBridgeSettings")
        window.center()
        return NSWindowController(window: window)
    }

    func windowWillClose(_ notification: Notification) {
        guard
            let closingWindow = notification.object as? NSWindow,
            closingWindow === settingsWindowController?.window
        else {
            return
        }

        closingWindow.contentViewController = nil
        settingsWindowController = nil
    }

    @objc private func showLog() {
        model.openLogFolder()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
