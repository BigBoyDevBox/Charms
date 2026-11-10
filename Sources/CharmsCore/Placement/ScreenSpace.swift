import CoreGraphics
import Foundation

/// A connected display in AppKit global coordinates: origin at the bottom-left
/// corner of the primary display, Y increasing upwards.
public struct DisplayGeometry: Equatable, Sendable {
    /// The whole display, including the menu bar and Dock areas.
    public let frame: CGRect
    /// The part of the display windows may normally use.
    public let visibleFrame: CGRect
    /// The display that carries the coordinate origin (the menu-bar display).
    public let isPrimary: Bool

    public init(frame: CGRect, visibleFrame: CGRect, isPrimary: Bool) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.isPrimary = isPrimary
    }
}

/// Conversion between the two global coordinate spaces Charms meets.
///
/// Accessibility and Quartz report rectangles with the origin at the TOP-left
/// of the primary display and Y increasing downwards. AppKit places windows
/// with the origin at the BOTTOM-left of the primary display and Y increasing
/// upwards. X is identical in both. Only Y is reflected, and always around
/// the primary display's full frame, whichever display the rectangle is on.
/// Reflecting around the destination display's height, or around a
/// `visibleFrame`, is the classic way to put a window on the wrong screen.
public enum ScreenSpace {
    public static func appKitRect(fromAccessibility rect: CGRect, primaryFrame: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryFrame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The reflection is its own inverse; this name exists for readability.
    public static func accessibilityRect(fromAppKit rect: CGRect, primaryFrame: CGRect) -> CGRect {
        appKitRect(fromAccessibility: rect, primaryFrame: primaryFrame)
    }

    public static func appKitPoint(fromAccessibility point: CGPoint, primaryFrame: CGRect) -> CGPoint {
        CGPoint(x: point.x, y: primaryFrame.maxY - point.y)
    }

    /// The primary display's frame, or nil when no display is connected.
    public static func primaryFrame(in displays: [DisplayGeometry]) -> CGRect? {
        (displays.first(where: \.isPrimary) ?? displays.first)?.frame
    }
}

extension CGRect {
    /// True when every component is a finite number.
    var isFinite: Bool {
        origin.x.isFinite && origin.y.isFinite && size.width.isFinite && size.height.isFinite
    }

    var area: CGFloat {
        isNull || isInfinite ? 0 : width * height
    }
}
