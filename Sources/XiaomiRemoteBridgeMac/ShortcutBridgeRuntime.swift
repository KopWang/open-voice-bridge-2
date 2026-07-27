import Foundation

final class ShortcutBridgeRuntime {
    let settings: ShortcutBridgeSettings

    private let emitter: ShortcutEmitter
    private let monitor: ShortcutHIDMonitor

    var onStatus: ((String) -> Void)? {
        didSet { monitor.onStatus = onStatus }
    }

    var onConnectionChange: ((Bool) -> Void)? {
        didSet { monitor.onConnectionChange = onConnectionChange }
    }

    var status: String { monitor.status }
    var isConnected: Bool { monitor.isConnected }
    var isExclusivelyReading: Bool { monitor.isExclusivelyReading }

    init(
        settings: ShortcutBridgeSettings = ShortcutBridgeSettings(),
        eventSink: ShortcutEventSink = CGShortcutEventSink()
    ) {
        self.settings = settings
        emitter = ShortcutEmitter(sink: eventSink)
        monitor = ShortcutHIDMonitor(settings: settings, emitter: emitter)
    }

    func start() {
        monitor.start()
    }

    func stop() {
        monitor.stop()
    }

    func refresh() {
        monitor.refresh()
    }

    func setBinding(_ binding: ShortcutBinding, for button: RemoteButton) {
        _ = emitter.replaceBinding(for: button)
        settings.setBinding(binding, for: button)
    }

    func resetBindings() {
        _ = emitter.forceReleaseAll(reason: "restore_defaults")
        settings.resetBindings()
    }
}
