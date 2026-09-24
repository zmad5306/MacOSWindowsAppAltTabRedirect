import XCTest
@testable import AltTabCore

final class ShortcutDecisionEngineTests: XCTestCase {
    func testForwardShortcutReplacesCommandWithOption() {
        var engine = ShortcutDecisionEngine()
        pressLeftCommand(&engine, eligible: true)

        let action = engine.handle(
            .init(kind: .keyDown, keyCode: 48, modifiers: [.command]),
            isEligible: true
        )

        XCTAssertEqual(action, .replace(keyCode: 48, modifiers: [.option]))
    }

    func testReverseShortcutPreservesShiftAndReplacesCommandWithOption() {
        var engine = ShortcutDecisionEngine()
        pressLeftCommand(&engine, eligible: true)

        for kind in [ShortcutEventKind.keyDown, .keyUp] {
            XCTAssertEqual(
                engine.handle(
                    .init(kind: kind, keyCode: 48, modifiers: [.command, .shift]),
                    isEligible: true
                ),
                .replace(keyCode: 48, modifiers: [.option, .shift])
            )
        }
    }

    func testRepeatedTabsAreTranslated() {
        var engine = ShortcutDecisionEngine()
        pressLeftCommand(&engine, eligible: true)

        for _ in 0..<3 {
            XCTAssertEqual(
                engine.handle(
                    .init(kind: .keyDown, keyCode: 48, modifiers: [.command]),
                    isEligible: true
                ),
                .replace(keyCode: 48, modifiers: [.option])
            )
        }
    }

    func testCommandPressAndReleaseBecomeOptionWhenActivated() {
        var engine = ShortcutDecisionEngine()
        XCTAssertEqual(
            engine.handle(
                .init(
                    kind: .flagsChanged,
                    keyCode: 55,
                    modifiers: [.command],
                    physicalKeyDown: true
                ),
                isEligible: true
            ),
            .replace(keyCode: 58, modifiers: [.option])
        )
        XCTAssertEqual(
            engine.handle(
                .init(
                    kind: .flagsChanged,
                    keyCode: 55,
                    modifiers: [],
                    physicalKeyDown: false
                ),
                isEligible: false
            ),
            .replace(keyCode: 58, modifiers: []),
            "A release remains redirected if its matching press was redirected"
        )
    }

    func testRightCommandDoesNotTrigger() {
        var engine = ShortcutDecisionEngine()
        _ = engine.handle(
            .init(kind: .flagsChanged, keyCode: 54, modifiers: [.command], physicalKeyDown: true),
            isEligible: true
        )

        XCTAssertEqual(
            engine.handle(
                .init(kind: .keyDown, keyCode: 48, modifiers: [.command]),
                isEligible: true
            ),
            .passThrough
        )
    }

    func testIneligibleAndExtraModifierShortcutsPassThrough() {
        var engine = ShortcutDecisionEngine()
        pressLeftCommand(&engine, eligible: false)
        XCTAssertEqual(
            engine.handle(
                .init(kind: .keyDown, keyCode: 48, modifiers: [.command]),
                isEligible: false
            ),
            .passThrough
        )

        pressLeftCommand(&engine, eligible: true)
        for modifiers: ShortcutModifiers in [[.command, .option], [.command, .control]] {
            XCTAssertEqual(
                engine.handle(
                    .init(kind: .keyDown, keyCode: 48, modifiers: modifiers),
                    isEligible: true
                ),
                .passThrough
            )
        }
    }

    private func pressLeftCommand(
        _ engine: inout ShortcutDecisionEngine,
        eligible: Bool
    ) {
        _ = engine.handle(
            .init(
                kind: .flagsChanged,
                keyCode: 55,
                modifiers: [.command],
                physicalKeyDown: true
            ),
            isEligible: eligible
        )
    }
}
