import Foundation

final class Diagnostics {
    static let shared = Diagnostics()
    static let fileURL = URL(fileURLWithPath: "/tmp/windows-alt-tab-redirect-status.txt")

    private let queue = DispatchQueue(label: "WindowsAltTabRedirect.Diagnostics")
    private var values: [String: String] = [:]
    private var recentEvents: [String] = []

    private init() {}

    func set(_ key: String, _ value: String) {
        queue.async { [self] in
            values[key] = value
            writeFile()
        }
    }

    func recordEvent(_ value: String) {
        queue.async { [self] in
            recentEvents.append(value)
            recentEvents = Array(recentEvents.suffix(16))
            values["eventTrace"] = recentEvents.joined(separator: " | ")
            writeFile()
        }
    }

    private func writeFile() {
        values["updated"] = ISO8601DateFormatter().string(from: Date())
        let contents = values.keys.sorted().map { "\($0)=\(values[$0]!)" }.joined(separator: "\n") + "\n"
        try? contents.data(using: .utf8)?.write(to: Self.fileURL, options: .atomic)
    }
}
