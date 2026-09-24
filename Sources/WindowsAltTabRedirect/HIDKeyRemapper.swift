import Foundation

/// Applies the remap below Quartz, so Windows App sees a physical Option key.
/// Windows App reads hardware modifier state and ignores modifier state attached
/// only to synthetic CGEvents.
final class HIDKeyRemapper {
    private struct Mapping: Equatable {
        let source: UInt64
        let destination: UInt64

        var dictionary: [String: UInt64] {
            [
                "HIDKeyboardModifierMappingSrc": source,
                "HIDKeyboardModifierMappingDst": destination,
            ]
        }
    }

    // USB HID usage page 0x07, Left GUI (Command) and Left Alt (Option).
    private static let leftCommand: UInt64 = 0x7000_000E3
    private static let leftOption: UInt64 = 0x7000_000E2
    private static let redirectMapping = Mapping(
        source: leftCommand,
        destination: leftOption
    )

    private let baselineMappings: [Mapping]
    private(set) var isActive = false

    init() {
        // If a previous copy crashed while its mapping was active, do not adopt
        // that mapping as the user's baseline.
        baselineMappings = Self.readMappings().filter { $0 != Self.redirectMapping }
        _ = apply(baselineMappings)
    }

    @discardableResult
    func setActive(_ active: Bool) -> Bool {
        guard active != isActive else { return true }

        let mappings: [Mapping]
        if active {
            mappings = baselineMappings.filter { $0.source != Self.leftCommand }
                + [Self.redirectMapping]
        } else {
            mappings = baselineMappings
        }

        var succeeded = false
        for _ in 0..<3 {
            guard apply(mappings) else { continue }
            let installed = Self.readMappings()
            if active {
                succeeded = installed.contains(Self.redirectMapping)
            } else {
                succeeded = !installed.contains(Self.redirectMapping)
            }
            if succeeded { break }
        }
        if succeeded {
            isActive = active
        }
        Diagnostics.shared.set(
            "hidRemap",
            succeeded ? (active ? "active" : "restored") : "failed"
        )
        return succeeded
    }

    func restore() {
        guard isActive else { return }
        _ = setActive(false)
    }

    deinit {
        restore()
    }

    private func apply(_ mappings: [Mapping]) -> Bool {
        let property: [String: Any] = [
            "UserKeyMapping": mappings.map(\.dictionary),
        ]
        guard JSONSerialization.isValidJSONObject(property),
              let data = try? JSONSerialization.data(withJSONObject: property),
              let json = String(data: data, encoding: .utf8)
        else {
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--set", json]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            Diagnostics.shared.set("hidRemapError", error.localizedDescription)
            return false
        }
    }

    private static func readMappings() -> [Mapping] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--get", "UserKeyMapping"]
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let pattern = #"HIDKeyboardModifierMappingDst\s*=\s*(\d+);\s*HIDKeyboardModifierMappingSrc\s*=\s*(\d+);"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        return expression.matches(in: text, range: range).compactMap { match in
            guard let destinationRange = Range(match.range(at: 1), in: text),
                  let sourceRange = Range(match.range(at: 2), in: text),
                  let destination = UInt64(text[destinationRange]),
                  let source = UInt64(text[sourceRange])
            else { return nil }
            return Mapping(source: source, destination: destination)
        }
    }
}
