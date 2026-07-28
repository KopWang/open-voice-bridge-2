// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenVoiceBridge",
    platforms: [.macOS(.v11)],
    products: [
        .executable(
            name: "XiaomiRemoteBridgeMac",
            targets: ["XiaomiRemoteBridgeMac"]
        )
    ],
    targets: [
        .executableTarget(
            name: "XiaomiRemoteBridgeMac",
            path: "Sources/XiaomiRemoteBridgeMac",
            exclude: [
                "ATVVProtocol.swift",
                "AppSettings.swift",
                "AudioOutput.swift",
                "AudioPathDiagnostics.swift",
                "BluetoothLifecycle.swift",
                "BridgeAppModel.swift",
                "DeviceProfileCatalog.swift",
                "ExternalMicrophoneProfile.swift",
                "FunctionKeyMonitor.swift",
                "HIDRemoteMonitor.swift",
                "LocalMicrophoneArbitration.swift",
                "LocalMicrophoneBridge.swift",
                "LocalMicrophoneCapture.swift",
                "RemoteVoiceFunctionMapper.swift",
                "RemoteVoiceKeyMonitor.swift",
                "SettingsView.swift",
                "TestTone.swift",
                "VoiceBridgeDeviceProfile.swift",
                "VoiceFunctionKeyLatch.swift",
                "XiaomiBluetoothBridge.swift",
            ],
            sources: [
                "AppLogger.swift",
                "CGShortcutEventSink.swift",
                "KeyboardEventSuppressor.swift",
                "KeyboardInjector.swift",
                "LaunchAtLoginManager.swift",
                "RemoteButtonEdgeTracker.swift",
                "RemoteButtonChord.swift",
                "RemoteButtons.swift",
                "RemoteDeviceLifecycle.swift",
                "RemoteInputRouter.swift",
                "ShortcutBinding.swift",
                "ShortcutBridgeAppModel.swift",
                "ShortcutBridgeRuntime.swift",
                "ShortcutBridgeSettings.swift",
                "ShortcutCaptureEventTap.swift",
                "ShortcutEmitter.swift",
                "ShortcutHIDMonitor.swift",
                "ShortcutRecorder.swift",
                "ShortcutSettingsView.swift",
                "XiaomiRemoteBridgeMacApp.swift",
            ]
        ),
        .testTarget(
            name: "XiaomiRemoteBridgeMacTests",
            dependencies: ["XiaomiRemoteBridgeMac"],
            path: "Tests/XiaomiRemoteBridgeMacTests",
            exclude: [
                "ATVVProtocolTests.swift",
                "AudioPathDiagnosticsTests.swift",
                "BluetoothLifecycleTests.swift",
                "DeviceProfileCatalogTests.swift",
                "ExternalMicrophoneProfileTests.swift",
                "LocalMicrophoneArbitrationTests.swift",
                "RemoteButtonsTests.swift",
                "RemoteVoiceFunctionMapperTests.swift",
                "TestToneTests.swift",
                "VoiceBridgeDeviceProfileTests.swift",
                "VoiceFunctionKeyLatchTests.swift",
            ],
            sources: [
                "AppLoggerTests.swift",
                "ControllerOnlyWiringTests.swift",
                "ControllerRemoteButtonsTests.swift",
                "LaunchAtLoginManagerTests.swift",
                "ProductIdentityTests.swift",
                "RemoteInputRouterTests.swift",
                "ShortcutBindingTests.swift",
                "ShortcutBridgeSettingsTests.swift",
                "ShortcutCaptureEventTapTests.swift",
                "ShortcutEmitterTests.swift",
                "ShortcutHIDRuntimeTests.swift",
                "ShortcutRecorderTests.swift",
            ]
        ),
    ],
    swiftLanguageModes: [SwiftLanguageMode.v5]
)
