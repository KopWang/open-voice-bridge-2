import Foundation

enum RemoteDeviceMatchOutcome: Equatable {
    case ignored
    case unreadable
    case present(generation: UInt64)
}

struct RemoteDeviceLifecycle {
    private(set) var pipelineOpen = false
    private(set) var activeGeneration: UInt64?
    private var counter: UInt64 = 0

    var devicePresent: Bool {
        activeGeneration != nil
    }

    mutating func openPipeline() {
        pipelineOpen = true
        activeGeneration = nil
    }

    mutating func closePipeline() {
        pipelineOpen = false
        activeGeneration = nil
    }

    mutating func matched(
        openSucceeded: Bool
    ) -> RemoteDeviceMatchOutcome {
        guard pipelineOpen, activeGeneration == nil else {
            return .ignored
        }
        guard openSucceeded else {
            return .unreadable
        }
        counter &+= 1
        activeGeneration = counter
        return .present(generation: counter)
    }

    mutating func removed() -> UInt64? {
        guard let generation = activeGeneration else { return nil }
        activeGeneration = nil
        return generation
    }

    func accepts(generation: UInt64) -> Bool {
        activeGeneration == generation
    }
}
