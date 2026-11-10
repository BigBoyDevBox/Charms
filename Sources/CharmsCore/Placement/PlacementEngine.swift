import CoreGraphics
import Foundation

/// Everything known about where the user is typing, in AppKit global
/// coordinates, captured before the picker shows any window of its own.
public struct PlacementRequest: Equatable, Sendable {
    public var caret: CaretEstimate?
    /// Frame of the focused text field or text area.
    public var field: CGRect?
    /// Frame of the focused window.
    public var window: CGRect?
    /// Pointer location, used only when nothing above is usable.
    public var mouse: CGPoint?
    public var displays: [DisplayGeometry]
    public var panelSize: CGSize

    public init(caret: CaretEstimate? = nil, field: CGRect? = nil, window: CGRect? = nil, mouse: CGPoint? = nil, displays: [DisplayGeometry], panelSize: CGSize) {
        self.caret = caret
        self.field = field
        self.window = window
        self.mouse = mouse
        self.displays = displays
        self.panelSize = panelSize
    }
}

public struct Placement: Equatable, Sendable {
    /// What decided the position, in priority order.
    public enum Source: String, Sendable {
        case caret
        case field
        case window
        case mouse
        case primaryDisplay
    }

    public enum Side: String, Sendable {
        /// Under the anchor, the preferred side.
        case below
        /// Flipped over the anchor because there was no room underneath.
        case above
        /// Neither side fits; the panel is clamped and may cover the anchor.
        case clamped
        /// Positioned inside an area rather than beside an anchor.
        case inside
    }

    /// The panel's frame, AppKit global coordinates.
    public let frame: CGRect
    /// Index into the request's `displays`.
    public let displayIndex: Int
    public let source: Source
    public let side: Side

    public init(frame: CGRect, displayIndex: Int, source: Source, side: Side) {
        self.frame = frame
        self.displayIndex = displayIndex
        self.source = source
        self.side = side
    }
}

/// Decides where the picker appears.
///
/// The display is always chosen from where the user is typing: the caret,
/// else the focused field, else the focused window. The pointer's display is
/// consulted only when none of those is known, and the primary display only
/// when even the pointer is nowhere. No remembered position and no notion of
/// a "main" screen take part.
public enum PlacementEngine {
    /// Distance kept from the edges of the usable display area.
    public static let margin: CGFloat = 12
    /// Distance between the anchor and the panel.
    public static let gap: CGFloat = 6
    /// How far the panel's leading edge sits left of the caret, so the caret
    /// lines up with the search text rather than with the panel border.
    public static let leadingOffset: CGFloat = 18
    /// Fields up to this height are anchored like a caret; taller ones are
    /// text areas whose caret is somewhere unknown inside them.
    public static let compactFieldHeight: CGFloat = 64
    /// Vertical position of the panel's centre inside an area, as a fraction
    /// of the area's height measured from its bottom.
    public static let areaCentreFraction: CGFloat = 0.62

    public static func place(_ request: PlacementRequest) -> Placement? {
        let indices = request.displays.indices.filter { index in
            let frame = request.displays[index].frame
            return frame.isFinite && frame.width > 0 && frame.height > 0
        }
        guard !indices.isEmpty, request.panelSize.width > 0, request.panelSize.height > 0 else { return nil }

        if let caret = request.caret, let placement = placeBesideCaret(caret, request: request, indices: indices) {
            return placement
        }
        if let field = usableArea(request.field), let placement = placeForField(field, request: request, indices: indices) {
            return placement
        }
        if let window = usableArea(request.window), let index = displayWithGreatestOverlap(window, request: request, indices: indices) {
            let area = window.intersection(request.displays[index].visibleFrame)
            return placeInside(area.isNull || area.isEmpty ? request.displays[index].visibleFrame : area, displayIndex: index, source: .window, request: request)
        }
        if let mouse = request.mouse, mouse.x.isFinite, mouse.y.isFinite,
           let index = indices.first(where: { contains(request.displays[$0].frame, mouse) }) {
            return placeInside(request.displays[index].visibleFrame, displayIndex: index, source: .mouse, request: request)
        }
        let primary = indices.first(where: { request.displays[$0].isPrimary }) ?? indices[0]
        return placeInside(request.displays[primary].visibleFrame, displayIndex: primary, source: .primaryDisplay, request: request)
    }

    // MARK: - Anchored placement

    private static func placeBesideCaret(_ caret: CaretEstimate, request: PlacementRequest, indices: [Int]) -> Placement? {
        guard caret.line.isFinite, caret.keepVisible.isFinite else { return nil }
        let point = CGPoint(x: caret.line.midX, y: caret.line.midY)
        guard let index = indices.first(where: { contains(request.displays[$0].frame, point) }) else {
            // A caret that is on no connected display is stale geometry.
            return nil
        }
        return placeBeside(anchorX: caret.line.minX - leadingOffset, keepVisible: caret.keepVisible, displayIndex: index, source: .caret, request: request)
    }

    private static func placeForField(_ field: CGRect, request: PlacementRequest, indices: [Int]) -> Placement? {
        guard let index = displayWithGreatestOverlap(field, request: request, indices: indices) else { return nil }
        let visible = field.intersection(request.displays[index].visibleFrame)
        guard !visible.isNull, !visible.isEmpty else { return nil }
        if field.height <= compactFieldHeight {
            return placeBeside(anchorX: field.minX, keepVisible: visible, displayIndex: index, source: .field, request: request)
        }
        return placeInside(visible, displayIndex: index, source: .field, request: request)
    }

    private static func placeBeside(anchorX: CGFloat, keepVisible: CGRect, displayIndex: Int, source: Placement.Source, request: PlacementRequest) -> Placement {
        let usable = usableFrame(of: request.displays[displayIndex])
        let size = request.panelSize
        let x = clamp(anchorX, usable.minX, usable.maxX - size.width)

        let belowY = keepVisible.minY - gap - size.height
        if belowY >= usable.minY, belowY + size.height <= usable.maxY {
            return Placement(frame: CGRect(x: x, y: belowY, width: size.width, height: size.height), displayIndex: displayIndex, source: source, side: .below)
        }
        let aboveY = keepVisible.maxY + gap
        if aboveY + size.height <= usable.maxY, aboveY >= usable.minY {
            return Placement(frame: CGRect(x: x, y: aboveY, width: size.width, height: size.height), displayIndex: displayIndex, source: source, side: .above)
        }
        // Neither side fits. Keep the top of the panel, where the search field
        // is, on screen, and take the side with more room.
        let roomBelow = keepVisible.minY - usable.minY
        let roomAbove = usable.maxY - keepVisible.maxY
        let preferred = roomBelow >= roomAbove ? belowY : aboveY
        let y = clampTopVisible(preferred, height: size.height, usable: usable)
        return Placement(frame: CGRect(x: x, y: y, width: size.width, height: size.height), displayIndex: displayIndex, source: source, side: .clamped)
    }

    // MARK: - Area placement

    private static func placeInside(_ area: CGRect, displayIndex: Int, source: Placement.Source, request: PlacementRequest) -> Placement {
        let usable = usableFrame(of: request.displays[displayIndex])
        let size = request.panelSize
        let x = clamp(area.midX - size.width / 2, usable.minX, usable.maxX - size.width)
        let centreY = area.minY + area.height * areaCentreFraction
        let y = clampTopVisible(centreY - size.height / 2, height: size.height, usable: usable)
        return Placement(frame: CGRect(x: x, y: y, width: size.width, height: size.height), displayIndex: displayIndex, source: source, side: .inside)
    }

    // MARK: - Helpers

    private static func usableFrame(of display: DisplayGeometry) -> CGRect {
        let visible = display.visibleFrame.isFinite && display.visibleFrame.width > 0 && display.visibleFrame.height > 0
            ? display.visibleFrame
            : display.frame
        let inset = visible.insetBy(dx: margin, dy: margin)
        // A display too small for the margins still gets a placement.
        return inset.width > 0 && inset.height > 0 ? inset : visible
    }

    private static func usableArea(_ rect: CGRect?) -> CGRect? {
        guard let rect, rect.isFinite, rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }

    private static func displayWithGreatestOverlap(_ rect: CGRect, request: PlacementRequest, indices: [Int]) -> Int? {
        var bestIndex: Int?
        var bestArea: CGFloat = 0
        for index in indices {
            let overlap = rect.intersection(request.displays[index].frame).area
            // Strictly greater keeps the earlier display on a tie, which makes
            // the choice deterministic.
            guard overlap > bestArea else { continue }
            bestIndex = index
            bestArea = overlap
        }
        return bestIndex
    }

    /// `CGRect.contains` excludes the max edges; a caret sitting exactly on a
    /// display's right or top edge still belongs to that display.
    private static func contains(_ frame: CGRect, _ point: CGPoint) -> Bool {
        point.x >= frame.minX && point.x <= frame.maxX && point.y >= frame.minY && point.y <= frame.maxY
    }

    private static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        guard upper >= lower else { return lower }
        return min(max(value, lower), upper)
    }

    /// Clamps a panel vertically. When the panel is taller than the usable
    /// area its top edge wins, because the search field lives there.
    private static func clampTopVisible(_ y: CGFloat, height: CGFloat, usable: CGRect) -> CGFloat {
        let highest = usable.maxY - height
        guard highest >= usable.minY else { return highest }
        return min(max(y, usable.minY), highest)
    }
}
