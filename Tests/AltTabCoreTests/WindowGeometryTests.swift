import CoreGraphics
import XCTest
@testable import AltTabCore

final class WindowGeometryTests: XCTestCase {
    private let primary = DisplayGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 25, width: 1512, height: 920)
    )
    private let secondary = DisplayGeometry(
        frame: CGRect(x: 1512, y: -100, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 1512, y: -75, width: 1920, height: 1055)
    )

    func testNativeFullScreenAlwaysQualifies() {
        XCTAssertTrue(
            WindowGeometry.isMaximized(
                windowFrame: .zero,
                isNativeFullScreen: true,
                displays: []
            )
        )
    }

    func testVisibleFrameMaximizedQualifies() {
        XCTAssertTrue(
            WindowGeometry.isMaximized(
                windowFrame: primary.visibleFrame,
                isNativeFullScreen: false,
                displays: [primary]
            )
        )
    }

    func testSmallGeometryDifferencesAreTolerated() {
        let nearlyFull = primary.frame.insetBy(dx: 4, dy: 4)
        XCTAssertTrue(
            WindowGeometry.isMaximized(
                windowFrame: nearlyFull,
                isNativeFullScreen: false,
                displays: [primary]
            )
        )
    }

    func testWindowedSessionDoesNotQualify() {
        XCTAssertFalse(
            WindowGeometry.isMaximized(
                windowFrame: CGRect(x: 100, y: 100, width: 1000, height: 700),
                isNativeFullScreen: false,
                displays: [primary]
            )
        )
    }

    func testNearlyFullWindowsAppFrameQualifies() {
        let reportedFrame = primary.visibleFrame.insetBy(dx: 18, dy: 12)
        XCTAssertTrue(
            WindowGeometry.isMaximized(
                windowFrame: reportedFrame,
                isNativeFullScreen: false,
                displays: [primary]
            )
        )
    }

    func testSecondaryDisplayQualifies() {
        XCTAssertTrue(
            WindowGeometry.isMaximized(
                windowFrame: secondary.frame,
                isNativeFullScreen: false,
                displays: [primary, secondary]
            )
        )
    }
}
