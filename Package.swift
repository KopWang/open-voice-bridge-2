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
            path: "Sources/XiaomiRemoteBridgeMac"
        ),
        .testTarget(
            name: "XiaomiRemoteBridgeMacTests",
            dependencies: ["XiaomiRemoteBridgeMac"],
            path: "Tests/XiaomiRemoteBridgeMacTests",
            exclude: [
                // Apple's standalone Command Line Tools omit XCTest. The same
                // contract is covered by Tests/SelfTest and the profile validator.
                "DeviceProfileCatalogTests.swift",
                "ExternalMicrophoneProfileTests.swift",
                "LocalMicrophoneArbitrationTests.swift",
            ]
        ),
    ],
    swiftLanguageModes: [SwiftLanguageMode.v5]
)
