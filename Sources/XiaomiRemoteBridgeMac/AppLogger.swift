import Foundation

enum RuntimeLogTimestamp {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

final class AppLogger {
    static let shared = AppLogger()

    let logURL: URL
    private let queue = DispatchQueue(label: "XiaomiRemoteBridgeMac.logger")

    private init() {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("RemoteShortcutBridge", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        logURL = base.appendingPathComponent("runtime.log")
    }

    func write(_ message: String) {
        let line = "\(RuntimeLogTimestamp.string(from: Date())) \(message)\n"
        queue.async { [logURL] in
            let data = Data(line.utf8)
            if FileManager.default.fileExists(atPath: logURL.path),
               let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } catch {
                    return
                }
            } else {
                try? data.write(to: logURL, options: .atomic)
            }
        }
    }
}
