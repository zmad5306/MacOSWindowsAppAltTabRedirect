import Foundation

final class KarabinerIntegration {
    static let ruleDescription = "Windows Alt-Tab Redirect (managed)"
    static let activeVariable = "windows_alt_tab_redirect_active"

    private let fileManager = FileManager.default
    private let cliURL = URL(
        fileURLWithPath: "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
    )
    private lazy var configurationURL = fileManager.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/karabiner/karabiner.json")
    private var prepared = false
    private var lastActive: Bool?

    var isInstalled: Bool {
        fileManager.isExecutableFile(atPath: cliURL.path)
    }

    func prepareIfPossible() -> Bool {
        if prepared { return true }
        guard isInstalled else {
            Diagnostics.shared.set("karabiner", "not-installed")
            return false
        }
        if !fileManager.fileExists(atPath: configurationURL.path) {
            do {
                try createInitialConfiguration()
            } catch {
                Diagnostics.shared.set("karabiner", "setup-required: \(error.localizedDescription)")
                return false
            }
        }

        do {
            try installManagedRule()
            prepared = true
            Diagnostics.shared.set("karabiner", "ready")
            setActive(false)
            return true
        } catch {
            Diagnostics.shared.set("karabiner", "configuration-error: \(error.localizedDescription)")
            return false
        }
    }

    func setActive(_ active: Bool) {
        guard prepared, lastActive != active else { return }
        lastActive = active

        let process = Process()
        process.executableURL = cliURL
        process.arguments = [
            "--set-variables",
            "{\"\(Self.activeVariable)\":\(active ? 1 : 0)}",
        ]
        do {
            try process.run()
            process.waitUntilExit()
            Diagnostics.shared.set(
                "karabinerVariable",
                process.terminationStatus == 0 ? (active ? "active" : "inactive") : "failed"
            )
        } catch {
            Diagnostics.shared.set("karabinerVariable", "failed: \(error.localizedDescription)")
        }
    }

    private func installManagedRule() throws {
        let data = try Data(contentsOf: configurationURL)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var profiles = root["profiles"] as? [[String: Any]],
              let selectedIndex = profiles.firstIndex(where: { ($0["selected"] as? Bool) == true })
        else {
            throw IntegrationError.noSelectedProfile
        }

        var profile = profiles[selectedIndex]
        var complex = profile["complex_modifications"] as? [String: Any] ?? [:]
        var rules = complex["rules"] as? [[String: Any]] ?? []
        rules.removeAll { ($0["description"] as? String) == Self.ruleDescription }
        rules.append(Self.managedRule)
        complex["rules"] = rules
        profile["complex_modifications"] = complex
        profiles[selectedIndex] = profile
        root["profiles"] = profiles

        let backupURL = configurationURL
            .deletingLastPathComponent()
            .appendingPathComponent("karabiner.json.windows-alt-tab-redirect.backup")
        if !fileManager.fileExists(atPath: backupURL.path) {
            try data.write(to: backupURL, options: .atomic)
        }

        let updated = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try updated.write(to: configurationURL, options: .atomic)
    }

    private func createInitialConfiguration() throws {
        try fileManager.createDirectory(
            at: configurationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let initial: [String: Any] = [
            "global": [
                "check_for_updates_on_startup": true,
                "show_in_menu_bar": true,
                "show_profile_name_in_menu_bar": false,
            ],
            "profiles": [[
                "name": "Default profile",
                "selected": true,
                "complex_modifications": ["rules": []],
                "virtual_hid_keyboard": [
                    "keyboard_type": "ansi",
                    "caps_lock_delay_milliseconds": 0,
                ],
            ]],
        ]
        let data = try JSONSerialization.data(
            withJSONObject: initial,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: configurationURL, options: .atomic)
    }

    private static var managedRule: [String: Any] {
        [
            "description": ruleDescription,
            "manipulators": [
                manipulator(
                    mandatory: ["left_command", "left_shift"],
                    outputModifiers: ["left_option", "left_shift"]
                ),
                manipulator(
                    mandatory: ["left_command"],
                    outputModifiers: ["left_option"]
                ),
            ],
        ]
    }

    private static func manipulator(
        mandatory: [String],
        outputModifiers: [String]
    ) -> [String: Any] {
        [
            "type": "basic",
            "from": [
                "key_code": "tab",
                "modifiers": ["mandatory": mandatory],
            ],
            "to": [[
                "key_code": "tab",
                "modifiers": outputModifiers,
            ]],
            "conditions": [
                [
                    "type": "variable_if",
                    "name": activeVariable,
                    "value": 1,
                ],
                [
                    "type": "frontmost_application_if",
                    "bundle_identifiers": ["^com\\.microsoft\\.rdc\\.macos$"],
                ],
            ],
        ]
    }

    private enum IntegrationError: LocalizedError {
        case noSelectedProfile

        var errorDescription: String? {
            "Karabiner does not have a selected profile yet"
        }
    }
}
