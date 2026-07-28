import Foundation
import Testing
@testable import XiaomiRemoteBridgeMac

@Suite("App logger")
struct AppLoggerTests {
    @Test func timestampIncludesMilliseconds() {
        #expect(
            RuntimeLogTimestamp.string(
                from: Date(timeIntervalSince1970: 0.123)
            ) == "1970-01-01T00:00:00.123Z"
        )
    }
}
