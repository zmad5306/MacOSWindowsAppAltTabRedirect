import AltTabCore
import AppKit
import ApplicationServices

enum SessionStatus: Equatable {
    case paused
    case permissionRequired
    case windowsAppNotFocused
    case noSession
    case windowedSession
    case active

    var description: String {
        switch self {
        case .paused: return "Paused"
        case .permissionRequired: return "Accessibility permission required"
        case .windowsAppNotFocused: return "Windows App is not focused"
        case .noSession: return "No focused RDP session"
        case .windowedSession: return "RDP session is not maximized"
        case .active: return "Redirecting Command+Tab"
        }
    }
}

final class SessionDetector {
    static let windowsAppBundleIdentifier = "com.microsoft.rdc.macos"

    private let isEnabled: () -> Bool
    private let onStatusChange: (SessionStatus) -> Void
    private var timer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var accessibilityObserver: AXObserver?
    private var observedPID: pid_t?
    private var observedWindow: AXUIElement?
    private(set) var status: SessionStatus = .windowsAppNotFocused

    init(
        isEnabled: @escaping () -> Bool,
        onStatusChange: @escaping (SessionStatus) -> Void
    ) {
        self.isEnabled = isEnabled
        self.onStatusChange = onStatusChange
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        let notifications: [Notification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        workspaceObservers = notifications.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers.removeAll()
        clearAccessibilityObserver()
    }

    func refresh() {
        guard isEnabled() else {
            update(.paused)
            return
        }
        guard AccessibilityPermission.isGranted else {
            update(.permissionRequired)
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == Self.windowsAppBundleIdentifier
        else {
            clearAccessibilityObserver()
            update(.windowsAppNotFocused)
            return
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        configureAccessibilityObserver(pid: app.processIdentifier, appElement: appElement)

        // Windows App intermittently omits AXFocusedWindow for an active RDP
        // window (notably after returning from System Settings). Fall back to
        // AXMainWindow and then the application's window list.
        guard let window = sessionWindow(in: appElement) else {
            update(.noSession)
            return
        }
        observeWindowIfNeeded(window)

        guard isLikelySessionWindow(window) else {
            update(.noSession)
            return
        }

        let isFullScreen = copyBoolAttribute(window, "AXFullScreen") ?? false
        guard let frame = windowFrame(window) else {
            Diagnostics.shared.set("windowGeometry", "unavailable")
            update(.windowedSession)
            return
        }
        Diagnostics.shared.set(
            "windowGeometry",
            "x=\(Int(frame.minX)) y=\(Int(frame.minY)) width=\(Int(frame.width)) height=\(Int(frame.height)) fullScreen=\(isFullScreen)"
        )

        guard WindowGeometry.isMaximized(
            windowFrame: frame,
            isNativeFullScreen: isFullScreen,
            displays: displayGeometryInAccessibilityCoordinates(),
            tolerance: 12
        ) else {
            update(.windowedSession)
            return
        }

        update(.active)
    }

    private func sessionWindow(in appElement: AXUIElement) -> AXUIElement? {
        if let focused = copyElementAttribute(appElement, kAXFocusedWindowAttribute) {
            return focused
        }

        if let main = copyElementAttribute(appElement, kAXMainWindowAttribute) {
            return main
        }

        return copyElementArrayAttribute(appElement, kAXWindowsAttribute)
            .first(where: isLikelySessionWindow)
    }

    deinit {
        stop()
    }

    private func update(_ newStatus: SessionStatus) {
        Diagnostics.shared.set("sessionStatus", newStatus.description)
        Diagnostics.shared.set("accessibility", AccessibilityPermission.isGranted ? "granted" : "denied")
        guard status != newStatus else {
            // Let the HID layer retry if macOS discarded a mapping during a
            // keyboard/device transition while the same session stayed active.
            if newStatus == .active {
                onStatusChange(newStatus)
            }
            return
        }
        status = newStatus
        onStatusChange(newStatus)
    }

    private func isLikelySessionWindow(_ window: AXUIElement) -> Bool {
        guard let role = copyStringAttribute(window, kAXRoleAttribute),
              role == kAXWindowRole as String
        else {
            return false
        }

        guard let title = copyStringAttribute(window, kAXTitleAttribute)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty
        else {
            return false
        }

        let excludedTitles = ["windows app", "settings", "preferences"]
        return !excludedTitles.contains(title.lowercased())
    }

    private func windowFrame(_ window: AXUIElement) -> CGRect? {
        guard let position = copyPointAttribute(window, kAXPositionAttribute),
              let size = copySizeAttribute(window, kAXSizeAttribute)
        else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func displayGeometryInAccessibilityCoordinates() -> [DisplayGeometry] {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return [] }
        let primaryTop = primary.frame.maxY

        func convert(_ rect: CGRect) -> CGRect {
            CGRect(
                x: rect.minX,
                y: primaryTop - rect.maxY,
                width: rect.width,
                height: rect.height
            )
        }

        return screens.map {
            DisplayGeometry(frame: convert($0.frame), visibleFrame: convert($0.visibleFrame))
        }
    }

    private func configureAccessibilityObserver(pid: pid_t, appElement: AXUIElement) {
        guard observedPID != pid else { return }
        clearAccessibilityObserver()

        var observer: AXObserver?
        let result = AXObserverCreate(pid, Self.accessibilityCallback, &observer)
        guard result == .success, let observer else { return }

        accessibilityObserver = observer
        observedPID = pid
        AXObserverAddNotification(
            observer,
            appElement,
            kAXFocusedWindowChangedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        )
        AXObserverAddNotification(
            observer,
            appElement,
            kAXWindowCreatedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        )
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
    }

    private func observeWindowIfNeeded(_ window: AXUIElement) {
        if let observedWindow, CFEqual(observedWindow, window) {
            return
        }

        if let observer = accessibilityObserver, let oldWindow = observedWindow {
            for notification in Self.windowNotifications {
                AXObserverRemoveNotification(observer, oldWindow, notification as CFString)
            }
        }
        observedWindow = window

        guard let observer = accessibilityObserver else { return }
        for notification in Self.windowNotifications {
            AXObserverAddNotification(
                observer,
                window,
                notification as CFString,
                Unmanaged.passUnretained(self).toOpaque()
            )
        }
    }

    private func clearAccessibilityObserver() {
        guard let observer = accessibilityObserver else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
        accessibilityObserver = nil
        observedWindow = nil
        observedPID = nil
    }

    private static let windowNotifications = [
        kAXMovedNotification,
        kAXResizedNotification,
        kAXTitleChangedNotification,
    ]

    private static let accessibilityCallback: AXObserverCallback = { _, _, _, refcon in
        guard let refcon else { return }
        let detector = Unmanaged<SessionDetector>
            .fromOpaque(refcon)
            .takeUnretainedValue()
        DispatchQueue.main.async {
            detector.refresh()
        }
    }
}

private func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
        return nil
    }
    return value
}

private func copyElementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    guard let value = copyAttribute(element, attribute),
          CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return nil }
    return unsafeBitCast(value, to: AXUIElement.self)
}

private func copyElementArrayAttribute(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
    guard let value = copyAttribute(element, attribute) as? [Any] else { return [] }
    return value.compactMap { item in
        let object = item as CFTypeRef
        guard CFGetTypeID(object) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(object, to: AXUIElement.self)
    }
}

private func copyStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
    copyAttribute(element, attribute) as? String
}

private func copyBoolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
    copyAttribute(element, attribute) as? Bool
}

private func copyPointAttribute(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
    guard let value = copyAttribute(element, attribute),
          CFGetTypeID(value) == AXValueGetTypeID()
    else { return nil }
    var point = CGPoint.zero
    guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cgPoint, &point) else {
        return nil
    }
    return point
}

private func copySizeAttribute(_ element: AXUIElement, _ attribute: String) -> CGSize? {
    guard let value = copyAttribute(element, attribute),
          CFGetTypeID(value) == AXValueGetTypeID()
    else { return nil }
    var size = CGSize.zero
    guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cgSize, &size) else {
        return nil
    }
    return size
}
