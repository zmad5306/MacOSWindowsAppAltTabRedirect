import CoreGraphics

public struct DisplayGeometry: Equatable, Sendable {
    public let frame: CGRect
    public let visibleFrame: CGRect

    public init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

public enum WindowGeometry {
    public static func isMaximized(
        windowFrame: CGRect,
        isNativeFullScreen: Bool,
        displays: [DisplayGeometry],
        tolerance: CGFloat = 8
    ) -> Bool {
        if isNativeFullScreen {
            return true
        }

        return displays.contains { display in
            fills(windowFrame, target: display.frame, tolerance: tolerance)
                || fills(windowFrame, target: display.visibleFrame, tolerance: tolerance)
        }
    }

    private static func fills(
        _ window: CGRect,
        target: CGRect,
        tolerance: CGFloat
    ) -> Bool {
        if approximatelyEqual(window, target, tolerance: tolerance) {
            return true
        }

        guard target.width > 0, target.height > 0 else { return false }
        let intersection = window.intersection(target)
        guard !intersection.isNull else { return false }

        // Windows App can report a frame a few more pixels inside the screen
        // than AppKit's visibleFrame. Coverage avoids rejecting a genuinely
        // zoomed window because of menu-bar, Dock, or shadow discrepancies,
        // while still rejecting ordinary window sizes.
        let widthCoverage = intersection.width / target.width
        let heightCoverage = intersection.height / target.height
        let areaCoverage = (intersection.width * intersection.height)
            / (target.width * target.height)
        return widthCoverage >= 0.96
            && heightCoverage >= 0.96
            && areaCoverage >= 0.94
    }

    private static func approximatelyEqual(
        _ lhs: CGRect,
        _ rhs: CGRect,
        tolerance: CGFloat
    ) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.maxX - rhs.maxX) <= tolerance
            && abs(lhs.maxY - rhs.maxY) <= tolerance
    }
}
