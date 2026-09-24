import AltTabCore
import ApplicationServices

final class EventTapController {
    private static let syntheticMarker: Int64 = 0x5741_5452

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var engine = ShortcutDecisionEngine()
    private let syntheticEventSource = CGEventSource(stateID: .hidSystemState)

    var isEligible = false

    var isRunning: Bool {
        eventTap != nil
    }

    func start() -> Bool {
        guard eventTap == nil else {
            Diagnostics.shared.set("eventTap", "running")
            return true
        }

        let eventTypes: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        let mask = eventTypes.reduce(CGEventMask(0)) { partial, type in
            partial | (CGEventMask(1) << CGEventMask(type.rawValue))
        }

        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: EventTapController.callback,
            userInfo: opaqueSelf
        ) else {
            Diagnostics.shared.set("eventTap", "creation-failed")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        Diagnostics.shared.set("eventTap", "running")
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        runLoopSource = nil
        eventTap = nil
        Diagnostics.shared.set("eventTap", "stopped")
    }

    deinit {
        stop()
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let controller = Unmanaged<EventTapController>
            .fromOpaque(userInfo)
            .takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = controller.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == syntheticMarker {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            Diagnostics.shared.recordEvent(
                "synthetic type=\(type.rawValue) keyCode=\(keyCode) flags=\(event.flags.rawValue)"
            )
            return Unmanaged.passUnretained(event)
        }

        guard let kind = ShortcutEventKind(type) else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let physicalKeyDown: Bool?
        if kind == .flagsChanged, keyCode == ShortcutDecisionEngine.KeyCode.leftCommand {
            // At a head-insert event tap, CGEventSource.keyState can still
            // report the state from before the flagsChanged event. The event's
            // own flags are authoritative for this transition.
            physicalKeyDown = event.flags.contains(.maskCommand)
        } else {
            physicalKeyDown = nil
        }

        let input = ShortcutInput(
            kind: kind,
            keyCode: keyCode,
            modifiers: ShortcutModifiers(event.flags),
            physicalKeyDown: physicalKeyDown
        )

        let action = controller.engine.handle(input, isEligible: controller.isEligible)
        if keyCode == ShortcutDecisionEngine.KeyCode.leftCommand
            || keyCode == ShortcutDecisionEngine.KeyCode.tab {
            Diagnostics.shared.recordEvent(
                "type=\(kind) keyCode=\(keyCode) eligible=\(controller.isEligible) action=\(action)"
            )
        }

        switch action {
        case .passThrough:
            return Unmanaged.passUnretained(event)
        case .suppress:
            return nil
        case let .replace(replacementKeyCode, modifiers):
            guard let replacement = CGEvent(
                keyboardEventSource: controller.syntheticEventSource,
                virtualKey: CGKeyCode(replacementKeyCode),
                keyDown: kind != .keyUp && !(kind == .flagsChanged && modifiers.isEmpty)
            ) else {
                Diagnostics.shared.recordEvent("synthetic creation failed")
                return nil
            }
            replacement.type = type
            replacement.flags = modifiers.cgEventFlags
            replacement.setIntegerValueField(
                .eventSourceUserData,
                value: syntheticMarker
            )
            if input.kind == .keyDown {
                replacement.setIntegerValueField(
                    .keyboardEventAutorepeat,
                    value: event.getIntegerValueField(.keyboardEventAutorepeat)
                )
            }
            replacement.post(tap: .cghidEventTap)
            return nil
        }
    }
}

private extension ShortcutEventKind {
    init?(_ eventType: CGEventType) {
        switch eventType {
        case .keyDown: self = .keyDown
        case .keyUp: self = .keyUp
        case .flagsChanged: self = .flagsChanged
        default: return nil
        }
    }
}

private extension ShortcutModifiers {
    init(_ flags: CGEventFlags) {
        self = []
        if flags.contains(.maskCommand) { insert(.command) }
        if flags.contains(.maskShift) { insert(.shift) }
        if flags.contains(.maskAlternate) { insert(.option) }
        if flags.contains(.maskControl) { insert(.control) }
    }

    var cgEventFlags: CGEventFlags {
        var result: CGEventFlags = []
        if contains(.command) { result.insert(.maskCommand) }
        if contains(.shift) { result.insert(.maskShift) }
        if contains(.option) { result.insert(.maskAlternate) }
        if contains(.control) { result.insert(.maskControl) }
        return result
    }
}
