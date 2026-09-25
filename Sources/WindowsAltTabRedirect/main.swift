import AppKit

private let enabledDefaultsKey = "redirectEnabled"

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController!
    private var sessionDetector: SessionDetector!
    private let karabiner = KarabinerIntegration()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [enabledDefaultsKey: true])
        Diagnostics.shared.set("process", "started")
        Diagnostics.shared.set(
            "accessibility",
            AccessibilityPermission.isGranted ? "granted" : "denied"
        )

        menuBarController = MenuBarController()
        menuBarController.isEnabled = UserDefaults.standard.bool(forKey: enabledDefaultsKey)
        menuBarController.onEnabledChanged = { [weak self] enabled in
            UserDefaults.standard.set(enabled, forKey: enabledDefaultsKey)
            self?.sessionDetector.refresh()
        }
        menuBarController.onPermissionRequested = { [weak self] in
            AccessibilityPermission.request()
            AccessibilityPermission.openSystemSettings()
            self?.sessionDetector.refresh()
        }

        sessionDetector = SessionDetector(
            isEnabled: { UserDefaults.standard.bool(forKey: enabledDefaultsKey) },
            onStatusChange: { [weak self] status in
                guard let self else { return }
                let karabinerReady = self.karabiner.prepareIfPossible()
                let active = karabinerReady && status == .active
                self.karabiner.setActive(active)
                self.menuBarController.update(
                    status: karabinerReady ? status : .karabinerRequired
                )
                Diagnostics.shared.set("eligible", active ? "true" : "false")
            }
        )

        if !AccessibilityPermission.isGranted {
            AccessibilityPermission.request()
        }
        sessionDetector.start()
        menuBarController.update(
            status: karabiner.prepareIfPossible()
                ? sessionDetector.status
                : .karabinerRequired
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessionDetector.stop()
        karabiner.setActive(false)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
