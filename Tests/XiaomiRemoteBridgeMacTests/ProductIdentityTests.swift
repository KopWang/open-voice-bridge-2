import Foundation
import Testing

@Suite("Product identity")
struct ProductIdentityTests {
    private func infoPlist() throws -> [String: Any] {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(
            contentsOf: repositoryRoot.appendingPathComponent("Resources/Info.plist")
        )
        return try #require(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        )
    }

    @Test func usesRemoteShortcutBridgeIdentity() throws {
        let plist = try infoPlist()

        #expect(plist["CFBundleDisplayName"] as? String == "遥控快捷桥")
        #expect(plist["CFBundleName"] as? String == "RemoteShortcutBridge")
        #expect(plist["CFBundleIdentifier"] as? String == "com.kopwang.RemoteShortcutBridge")
        #expect(plist["CFBundleShortVersionString"] as? String == "0.1.2")
        #expect(plist["CFBundleVersion"] as? String == "3")
    }

    @Test func declaresNoAudioOrApplicationBluetoothPrivacyUsage() throws {
        let plist = try infoPlist()

        #expect(plist["NSMicrophoneUsageDescription"] == nil)
        #expect(plist["NSBluetoothAlwaysUsageDescription"] == nil)
    }
}
