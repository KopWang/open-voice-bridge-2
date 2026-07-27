import Foundation
import Testing
@testable import XiaomiRemoteBridgeMac

@Suite("RC003 controller buttons")
struct ControllerRemoteButtonsTests {
    @Test func parsesKnownReports() {
        let raw = Data([0xF1, 0x00, 0x80, 0x00, 0x00, 0x00])
        let includedID = Data([0x01, 0x35, 0x00, 0x00, 0x00, 0x00, 0x00])

        #expect(RemoteHIDReportParser.usages(
            reportID: RC003ControllerIdentity.reportID,
            data: raw
        ) == [0xF1, 0x80])
        #expect(RemoteHIDReportParser.usages(
            reportID: RC003ControllerIdentity.reportID,
            data: includedID
        ) == [0x35])
    }

    @Test func exposesTheVerifiedThirteenControlTable() {
        #expect(RemoteButton.allCases.count == 13)
        #expect(RemoteButton.usageMap == [
            0x28: .ok,
            0x35: .tv,
            0x3E: .microphone,
            0x4A: .home,
            0x4F: .right,
            0x50: .left,
            0x51: .down,
            0x52: .up,
            0x65: .menu,
            0x66: .power,
            0x80: .volumeUp,
            0x81: .volumeDown,
            0xF1: .back,
        ])
    }
}
