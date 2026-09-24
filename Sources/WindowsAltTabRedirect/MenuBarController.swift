import AppKit
import ServiceManagement

final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let enabledMenuItem = NSMenuItem(title: "Enabled", action: nil, keyEquivalent: "")
    private let loginMenuItem = NSMenuItem(title: "Launch at Login", action: nil, keyEquivalent: "")

    var onEnabledChanged: ((Bool) -> Void)?
    var onPermissionRequested: (() -> Void)?

    var isEnabled = true {
        didSet { enabledMenuItem.state = isEnabled ? .on : .off }
    }

    override init() {
        super.init()
        statusItem.button?.image = NSImage(
            systemSymbolName: "rectangle.connected.to.line.below",
            accessibilityDescription: "Windows Alt-Tab Redirect"
        )
        statusItem.button?.toolTip = "Windows Alt-Tab Redirect"

        let menu = NSMenu()
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        enabledMenuItem.target = self
        enabledMenuItem.action = #selector(toggleEnabled)
        menu.addItem(enabledMenuItem)

        loginMenuItem.target = self
        loginMenuItem.action = #selector(toggleLaunchAtLogin)
        menu.addItem(loginMenuItem)

        let permissionItem = NSMenuItem(
            title: "Open Accessibility Settings…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        permissionItem.target = self
        menu.addItem(permissionItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "Quit Windows Alt-Tab Redirect",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        isEnabled = true
        refreshLaunchAtLoginState()
    }

    func update(status: SessionStatus) {
        statusMenuItem.title = status.description
        let active = status == .active
        statusItem.button?.image = NSImage(
            systemSymbolName: active
                ? "rectangle.connected.to.line.below.fill"
                : "rectangle.connected.to.line.below",
            accessibilityDescription: status.description
        )
        statusItem.button?.toolTip = "Windows Alt-Tab Redirect: \(status.description)"
    }

    @objc private func toggleEnabled() {
        isEnabled.toggle()
        onEnabledChanged?(isEnabled)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t update Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        refreshLaunchAtLoginState()
    }

    @objc private func openAccessibilitySettings() {
        onPermissionRequested?()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func refreshLaunchAtLoginState() {
        loginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}
