import CoreGraphics
import IOKit
import Testing
@testable import XiaomiRemoteBridgeMac

@Suite("Controller-only HID runtime")
struct ShortcutHIDRuntimeTests {
    @Test func pinsTheVerifiedRC003Identity() {
        #expect(RC003ControllerIdentity.vendorID == 0x2717)
        #expect(RC003ControllerIdentity.productID == 0x32B8)
        #expect(RC003ControllerIdentity.reportID == 1)
    }

    @Test func debouncesPressAndReleaseEdges() {
        var tracker = RemoteButtonEdgeTracker()

        #expect(tracker.update(usages: [0x003E]) == [
            RemoteButtonTransition(button: .microphone, edge: .down),
        ])
        #expect(tracker.update(usages: [0x003E]).isEmpty)
        #expect(tracker.update(usages: []).elementsEqual([
            RemoteButtonTransition(button: .microphone, edge: .up),
        ]))
    }

    @Test func routesAllThirteenControlsThroughOneTracker() {
        var tracker = RemoteButtonEdgeTracker()
        let usages = Set(RemoteButton.usageMap.keys)

        let downs = tracker.update(usages: usages)
        let ups = tracker.update(usages: [])

        #expect(Set(downs.map(\.button)) == Set(RemoteButton.allCases))
        #expect(downs.allSatisfy { $0.edge == .down })
        #expect(Set(ups.map(\.button)) == Set(RemoteButton.allCases))
        #expect(ups.allSatisfy { $0.edge == .up })
    }

    @Test func opensTheManagerOnceInStableMonitoredMode() {
        #expect(HIDManagerOpenPolicy.options == IOOptionBits(kIOHIDOptionsTypeNone))
        #expect(HIDManagerOpenPolicy.mode == .monitored)
    }

    @Test func suppressesNativeRemoteEventsAtTheHIDLayer() {
        #expect(
            KeyboardEventSuppressor.location.rawValue ==
                CGEventTapLocation.cghidEventTap.rawValue
        )
    }
}
