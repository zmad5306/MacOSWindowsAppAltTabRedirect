import Foundation

public struct ShortcutModifiers: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let command = ShortcutModifiers(rawValue: 1 << 0)
    public static let shift = ShortcutModifiers(rawValue: 1 << 1)
    public static let option = ShortcutModifiers(rawValue: 1 << 2)
    public static let control = ShortcutModifiers(rawValue: 1 << 3)
}

public enum ShortcutEventKind: Equatable, Sendable {
    case keyDown
    case keyUp
    case flagsChanged
}

public struct ShortcutInput: Equatable, Sendable {
    public let kind: ShortcutEventKind
    public let keyCode: UInt16
    public let modifiers: ShortcutModifiers
    public let physicalKeyDown: Bool?

    public init(
        kind: ShortcutEventKind,
        keyCode: UInt16,
        modifiers: ShortcutModifiers,
        physicalKeyDown: Bool? = nil
    ) {
        self.kind = kind
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.physicalKeyDown = physicalKeyDown
    }
}

public enum ShortcutAction: Equatable, Sendable {
    case passThrough
    case suppress
    case replace(keyCode: UInt16, modifiers: ShortcutModifiers)
}

public struct ShortcutDecisionEngine: Sendable {
    public enum KeyCode {
        public static let leftCommand: UInt16 = 55
        public static let leftOption: UInt16 = 58
        public static let tab: UInt16 = 48
    }

    private var leftCommandDown = false
    private var redirectLeftCommandRelease = false

    public init() {}

    public mutating func handle(_ input: ShortcutInput, isEligible: Bool) -> ShortcutAction {
        if input.kind == .flagsChanged, input.keyCode == KeyCode.leftCommand {
            let isDown = input.physicalKeyDown ?? input.modifiers.contains(.command)
            leftCommandDown = isDown

            if isDown, isEligible {
                redirectLeftCommandRelease = true
                return .replace(keyCode: KeyCode.leftOption, modifiers: [.option])
            }

            if !isDown, redirectLeftCommandRelease {
                redirectLeftCommandRelease = false
                return .replace(keyCode: KeyCode.leftOption, modifiers: [])
            }

            return .passThrough
        }

        guard isEligible,
              leftCommandDown,
              input.keyCode == KeyCode.tab,
              input.kind == .keyDown || input.kind == .keyUp
        else {
            return .passThrough
        }

        let disallowedModifiers: ShortcutModifiers = [.option, .control]
        guard input.modifiers.intersection(disallowedModifiers).isEmpty else {
            return .passThrough
        }

        let isReverse = input.modifiers.contains(.shift)
        return .replace(
            keyCode: KeyCode.tab,
            modifiers: isReverse ? [.option, .shift] : [.option]
        )
    }
}
