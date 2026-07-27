import Foundation

enum RC003ControllerIdentity {
    static let vendorID = 0x2717
    static let productID = 0x32B8
    static let reportID: UInt32 = 1
}

struct RemoteButtonTransition: Equatable {
    let button: RemoteButton
    let edge: RemoteEventEdge
}

struct RemoteButtonEdgeTracker {
    private var activeUsages = Set<UInt16>()

    mutating func update(usages: Set<UInt16>) -> [RemoteButtonTransition] {
        let pressed = usages.subtracting(activeUsages)
        let released = activeUsages.subtracting(usages)
        activeUsages = usages

        let downs = pressed.sorted().compactMap { usage in
            RemoteButton.usageMap[usage].map {
                RemoteButtonTransition(button: $0, edge: .down)
            }
        }
        let ups = released.sorted().compactMap { usage in
            RemoteButton.usageMap[usage].map {
                RemoteButtonTransition(button: $0, edge: .up)
            }
        }
        return downs + ups
    }

    mutating func reset() {
        activeUsages.removeAll()
    }
}
