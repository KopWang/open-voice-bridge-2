import Foundation
import Testing

@Suite("Controller-only production wiring")
struct ControllerOnlyWiringTests {
    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/XiaomiRemoteBridgeMac")
    }

    private func source(_ name: String) throws -> String {
        try String(
            contentsOf: sourceRoot.appendingPathComponent(name),
            encoding: .utf8
        )
    }

    @Test func appConstructsOnlyTheShortcutBridgeModel() throws {
        let app = try source("XiaomiRemoteBridgeMacApp.swift")

        #expect(app.contains("private let model = ShortcutBridgeAppModel()"))
        #expect(!app.contains("private let model = BridgeAppModel()"))
    }

    @Test func productionBoundaryHasNoAudioOrBluetoothServices() throws {
        let names = [
            "ShortcutBridgeAppModel.swift",
            "ShortcutBridgeRuntime.swift",
            "ShortcutSettingsView.swift",
            "XiaomiRemoteBridgeMacApp.swift",
        ]
        let forbidden = [
            "XiaomiBluetoothBridge",
            "VirtualAudioOutput",
            "LocalMicrophoneBridge",
            "RemoteVoiceFunctionMapper",
            "RemoteVoiceKeyMonitor",
        ]

        for name in names {
            let content = try source(name)
            for symbol in forbidden {
                #expect(!content.contains(symbol))
            }
        }
    }

    @Test func usesNewLoginAndLogIdentity() throws {
        let login = try source("LaunchAtLoginManager.swift")
        let logger = try source("AppLogger.swift")

        #expect(login.contains("com.kopwang.RemoteShortcutBridge"))
        #expect(logger.contains("RemoteShortcutBridge"))
        #expect(!logger.contains("appendingPathComponent(\"XiaomiRemoteBridgeMac\""))
    }
}
