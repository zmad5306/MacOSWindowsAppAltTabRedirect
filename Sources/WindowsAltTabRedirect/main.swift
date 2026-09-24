import AppKit

private let enabledDefaultsKey = "redirectEnabled"

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController!
    private var sessionDetector: SessionDetector!
    private let eventTapController = EventTapController()
    private let hidKeyRemapper = HIDKeyRemapper()

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
                self.menuBarController.update(status: status)
                self.eventTapController.isEligible = status == .active
                _ = self.hidKeyRemapper.setActive(status == .active)
                Diagnostics.shared.set("eligible", status == .active ? "true" : "false")
                if AccessibilityPermission.isGranted, !self.eventTapController.isRunning {
                    let started = self.eventTapController.start()
                    Diagnostics.shared.set("eventTapStart", started ? "succeeded" : "failed")
                }
            }
        )

        if !AccessibilityPermission.isGranted {
            AccessibilityPermission.request()
        }
        sessionDetector.start()
        if AccessibilityPermission.isGranted, !eventTapController.isRunning {
            let started = eventTapController.start()
            Diagnostics.shared.set("eventTapStart", started ? "succeeded" : "failed")
        }
        menuBarController.update(status: sessionDetector.status)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hidKeyRemapper.restore()
        sessionDetector.stop()
        eventTapController.stop()
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
