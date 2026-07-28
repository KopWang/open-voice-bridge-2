import Foundation

final class ShortcutBridgeRuntime {
    let settings: ShortcutBridgeSettings

    private let router: RemoteInputRouter
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
        let emitter = ShortcutEmitter(sink: eventSink)
        router = RemoteInputRouter(settings: settings, emitter: emitter)
        monitor = ShortcutHIDMonitor(router: router)
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
        _ = router.forceReleaseAll(reason: "single_binding_changed")
        settings.setBinding(binding, for: button)
    }

    func setCombinationBinding(
        _ binding: ShortcutBinding,
        for chord: RemoteButtonChord
    ) {
        _ = router.forceReleaseAll(reason: "combination_binding_changed")
        settings.setCombinationBinding(binding, for: chord)
    }

    func removeCombination(_ chord: RemoteButtonChord) {
        _ = router.forceReleaseAll(reason: "combination_removed")
        settings.removeCombination(chord)
    }

    func resetBindings() {
        _ = router.forceReleaseAll(reason: "restore_defaults")
        settings.resetBindings()
    }
}
