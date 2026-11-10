import XCTest
@testable import CharmsCore

/// Display arrangement used throughout: a 1920x1080 primary with a 30 pt menu
/// bar and a 90 pt Dock, a 1280x800 display to its left (so X is negative),
/// and a 1920x1080 display above it.
private enum Displays {
    static let primary = DisplayGeometry(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 90, width: 1920, height: 960),
        isPrimary: true
    )
    static let left = DisplayGeometry(
        frame: CGRect(x: -1280, y: 180, width: 1280, height: 800),
        visibleFrame: CGRect(x: -1280, y: 180, width: 1280, height: 800),
        isPrimary: false
    )
    static let above = DisplayGeometry(
        frame: CGRect(x: 0, y: 1080, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 1080, width: 1920, height: 1080),
        isPrimary: false
    )
    static let all = [primary, left, above]
}

private let pickerSize = CGSize(width: 400, height: 300)

private func confirmed(_ line: CGRect) -> CaretEstimate {
    CaretEstimate(line: line, keepVisible: line, evidence: .confirmedByPreviousCharacter)
}

final class ScreenSpaceTests: XCTestCase {
    func testReflectsYAroundThePrimaryFullFrame() {
        // Measured in TextEdit: character box at AX (262.73, 109), 15 x 13.
        let converted = ScreenSpace.appKitRect(fromAccessibility: CGRect(x: 262.5, y: 109, width: 15, height: 13), primaryFrame: Displays.primary.frame)
        XCTAssertEqual(converted, CGRect(x: 262.5, y: 958, width: 15, height: 13))
    }

    func testUsesFullFrameNotVisibleFrame() {
        // Reflecting around the visible frame would be off by the Dock height.
        let viaFull = ScreenSpace.appKitRect(fromAccessibility: CGRect(x: 0, y: 0, width: 10, height: 10), primaryFrame: Displays.primary.frame)
        XCTAssertEqual(viaFull.minY, 1070)
    }

    func testDisplayLeftOfPrimaryKeepsNegativeX() {
        // The left display's top edge is at AppKit Y 980, which is AX Y 100.
        let ax = CGRect(x: -1000, y: 200, width: 0, height: 16)
        let converted = ScreenSpace.appKitRect(fromAccessibility: ax, primaryFrame: Displays.primary.frame)
        XCTAssertEqual(converted, CGRect(x: -1000, y: 864, width: 0, height: 16))
        XCTAssertTrue(Displays.left.frame.contains(CGPoint(x: converted.midX, y: converted.midY)))
    }

    func testDisplayAbovePrimaryHasNegativeAccessibilityY() {
        let ax = CGRect(x: 500, y: -500, width: 0, height: 20)
        let converted = ScreenSpace.appKitRect(fromAccessibility: ax, primaryFrame: Displays.primary.frame)
        XCTAssertEqual(converted, CGRect(x: 500, y: 1560, width: 0, height: 20))
        XCTAssertTrue(Displays.above.frame.contains(CGPoint(x: converted.midX, y: converted.midY)))
    }

    func testConversionIsItsOwnInverse() {
        let rects = [
            CGRect(x: -1280, y: 100, width: 1280, height: 800),
            CGRect(x: 0, y: -1080, width: 1920, height: 1080),
            CGRect(x: 12.5, y: 700.25, width: 0, height: 17)
        ]
        for rect in rects {
            let there = ScreenSpace.appKitRect(fromAccessibility: rect, primaryFrame: Displays.primary.frame)
            XCTAssertEqual(ScreenSpace.accessibilityRect(fromAppKit: there, primaryFrame: Displays.primary.frame), rect)
        }
    }

    func testPrimaryFrameLookup() {
        XCTAssertEqual(ScreenSpace.primaryFrame(in: [Displays.left, Displays.primary]), Displays.primary.frame)
        XCTAssertNil(ScreenSpace.primaryFrame(in: []))
    }
}

final class CaretGeometryTests: XCTestCase {
    private let window = CGRect(x: 213, y: 581, width: 656, height: 422)

    func testTextKitZeroLengthCaretIsMovedOntoThePreviousCharactersLine() {
        // Measured on macOS 27 in TextEdit and converted to AppKit space: the
        // zero-length rect sits one 13 pt line above the character it follows.
        let probe = CaretProbe(
            caret: CGRect(x: 277.75, y: 971, width: 0, height: 13),
            previousCharacter: CGRect(x: 262.75, y: 958, width: 15, height: 13)
        )
        let estimate = CaretGeometry.estimate(probe, container: window)
        XCTAssertEqual(estimate?.evidence, .confirmedByPreviousCharacter)
        XCTAssertEqual(estimate?.line, CGRect(x: 277.75, y: 958, width: 0, height: 13))
        XCTAssertEqual(estimate?.keepVisible, CGRect(x: 277.75, y: 958, width: 0, height: 13))
    }

    func testNextCharacterWinsAtTheStartOfAWrappedLine() {
        // Caret at the left margin of line two. The previous character ends
        // line one far to the right, so only the next character confirms.
        let probe = CaretProbe(
            caret: CGRect(x: 223, y: 958, width: 0, height: 13),
            previousCharacter: CGRect(x: 840, y: 958, width: 8, height: 13),
            nextCharacter: CGRect(x: 223, y: 945, width: 7, height: 13)
        )
        let estimate = CaretGeometry.estimate(probe, container: window)
        XCTAssertEqual(estimate?.evidence, .confirmedByNextCharacter)
        XCTAssertEqual(estimate?.line, CGRect(x: 223, y: 945, width: 0, height: 13))
    }

    func testUnconfirmedCaretKeepsOneExtraLineBelowClear() {
        // Empty document: no neighbours to consult.
        let probe = CaretProbe(caret: CGRect(x: 223, y: 971, width: 0, height: 13))
        let estimate = CaretGeometry.estimate(probe, container: window)
        XCTAssertEqual(estimate?.evidence, .unconfirmed)
        XCTAssertEqual(estimate?.line, CGRect(x: 223, y: 971, width: 0, height: 13))
        XCTAssertEqual(estimate?.keepVisible, CGRect(x: 223, y: 958, width: 0, height: 26))
    }

    func testZeroWidthPreviousCharacterIsNotEvidence() {
        // A newline reported as a zero-width box on the line above must not
        // drag the caret up onto that line.
        let probe = CaretProbe(
            caret: CGRect(x: 223, y: 945, width: 0, height: 13),
            previousCharacter: CGRect(x: 223, y: 958, width: 0, height: 13)
        )
        XCTAssertEqual(CaretGeometry.estimate(probe, container: window)?.evidence, .unconfirmed)
    }

    func testPreviousCharacterAloneGivesAnEstimateWithAGuardLine() {
        let probe = CaretProbe(previousCharacter: CGRect(x: 300, y: 900, width: 10, height: 16))
        let estimate = CaretGeometry.estimate(probe, container: window)
        XCTAssertEqual(estimate?.evidence, .previousCharacterOnly)
        XCTAssertEqual(estimate?.line, CGRect(x: 310, y: 900, width: 0, height: 16))
        XCTAssertEqual(estimate?.keepVisible, CGRect(x: 310, y: 884, width: 0, height: 32))
    }

    func testDistantNeighbourIsIgnored() {
        // Same X by coincidence, but ten lines away: unrelated geometry.
        let probe = CaretProbe(
            caret: CGRect(x: 223, y: 900, width: 0, height: 13),
            nextCharacter: CGRect(x: 223, y: 760, width: 7, height: 13)
        )
        XCTAssertEqual(CaretGeometry.estimate(probe, container: window)?.evidence, .unconfirmed)
    }

    func testImplausibleRectanglesAreRejected() {
        let candidates = [
            CGRect(x: 300, y: 900, width: 0, height: 0),
            CGRect(x: 300, y: 600, width: 600, height: 400),
            CGRect(x: CGFloat.nan, y: 900, width: 0, height: 13),
            CGRect(x: 300, y: CGFloat.infinity, width: 0, height: 13),
            CGRect(x: 300, y: 900, width: 0, height: 2)
        ]
        for rect in candidates {
            XCTAssertNil(CaretGeometry.estimate(CaretProbe(caret: rect), container: window), "\(rect)")
        }
    }

    func testCaretOutsideItsWindowIsStale() {
        // Scrolled far out of the window's frame.
        let probe = CaretProbe(caret: CGRect(x: 300, y: 200, width: 0, height: 13))
        XCTAssertNil(CaretGeometry.estimate(probe, container: window))
        // Without a container there is nothing to contradict it.
        XCTAssertNotNil(CaretGeometry.estimate(probe, container: nil))
    }

    func testCaretOneLineAboveTheWindowTopIsStillAccepted() {
        // The one-line-high quirk can put the first line's caret just above
        // the text area; that is the case the correction exists for.
        let probe = CaretProbe(caret: CGRect(x: 223, y: 1004, width: 0, height: 13))
        XCTAssertNotNil(CaretGeometry.estimate(probe, container: window))
    }

    func testShortSelectionIsKeptVisibleButTallOneIsNot() {
        let caret = CGRect(x: 400, y: 900, width: 0, height: 13)
        let previous = CGRect(x: 392, y: 900, width: 8, height: 13)
        let short = CaretProbe(caret: caret, previousCharacter: previous, selection: CGRect(x: 250, y: 900, width: 150, height: 13))
        XCTAssertEqual(CaretGeometry.estimate(short, container: window)?.keepVisible, CGRect(x: 250, y: 900, width: 150, height: 13))
        let tall = CaretProbe(caret: caret, previousCharacter: previous, selection: CGRect(x: 223, y: 640, width: 600, height: 273))
        XCTAssertEqual(CaretGeometry.estimate(tall, container: window)?.keepVisible, caret)
    }
}

final class PlacementEngineTests: XCTestCase {
    private func request(caret: CaretEstimate? = nil, field: CGRect? = nil, window: CGRect? = nil, mouse: CGPoint? = nil,
                         displays: [DisplayGeometry] = Displays.all, size: CGSize = pickerSize) -> PlacementRequest {
        PlacementRequest(caret: caret, field: field, window: window, mouse: mouse, displays: displays, panelSize: size)
    }

    func testCaretOnSecondaryDisplayWinsOverMouseOnPrimary() {
        let caret = confirmed(CGRect(x: -1000, y: 864, width: 0, height: 16))
        let placement = PlacementEngine.place(request(caret: caret, mouse: CGPoint(x: 1200, y: 800)))
        XCTAssertEqual(placement?.source, .caret)
        XCTAssertEqual(placement?.displayIndex, 1)
        XCTAssertEqual(placement?.side, .below)
        // 18 pt left of the caret, 6 pt under the line, 300 pt tall.
        XCTAssertEqual(placement?.frame, CGRect(x: -1018, y: 558, width: 400, height: 300))
    }

    func testCaretOnDisplayAbovePrimary() {
        let caret = confirmed(CGRect(x: 500, y: 1560, width: 0, height: 20))
        let placement = PlacementEngine.place(request(caret: caret, mouse: CGPoint(x: 100, y: 100)))
        XCTAssertEqual(placement?.displayIndex, 2)
        XCTAssertEqual(placement?.frame, CGRect(x: 482, y: 1254, width: 400, height: 300))
    }

    func testFlipsAboveWhenThereIsNoRoomBelow() {
        // Usable area starts at Y 102 (Dock 90 + margin 12).
        let caret = confirmed(CGRect(x: 500, y: 100, width: 0, height: 16))
        let placement = PlacementEngine.place(request(caret: caret))
        XCTAssertEqual(placement?.side, .above)
        XCTAssertEqual(placement?.frame, CGRect(x: 482, y: 122, width: 400, height: 300))
    }

    func testClampsHorizontallyAtTheRightEdge() {
        let caret = confirmed(CGRect(x: 1900, y: 600, width: 0, height: 16))
        let placement = PlacementEngine.place(request(caret: caret))
        XCTAssertEqual(placement?.frame.minX, 1508)
        XCTAssertEqual(placement?.frame.maxX, 1908)
    }

    func testClampsHorizontallyAtTheLeftEdgeOfANegativeDisplay() {
        let caret = confirmed(CGRect(x: -1275, y: 700, width: 0, height: 16))
        let placement = PlacementEngine.place(request(caret: caret))
        XCTAssertEqual(placement?.displayIndex, 1)
        XCTAssertEqual(placement?.frame.minX, -1268)
    }

    func testUnconfirmedCaretLeavesItsGuardLineUncovered() {
        let estimate = CaretGeometry.estimate(CaretProbe(caret: CGRect(x: 300, y: 700, width: 0, height: 13)), container: nil)!
        let placement = PlacementEngine.place(request(caret: estimate))
        // Guard zone spans Y 687...713, so the panel top is at 681.
        XCTAssertEqual(placement?.frame.maxY, 681)
    }

    func testCaretOnNoDisplayFallsBackToTheWindow() {
        let caret = confirmed(CGRect(x: 5000, y: 5000, width: 0, height: 16))
        let window = CGRect(x: -1200, y: 300, width: 800, height: 500)
        let placement = PlacementEngine.place(request(caret: caret, window: window, mouse: CGPoint(x: 900, y: 500)))
        XCTAssertEqual(placement?.source, .window)
        XCTAssertEqual(placement?.displayIndex, 1)
    }

    func testCompactFieldIsAnchoredLikeADropDown() {
        let field = CGRect(x: 700, y: 980, width: 500, height: 28)
        let placement = PlacementEngine.place(request(field: field, mouse: CGPoint(x: -500, y: 500)))
        XCTAssertEqual(placement?.source, .field)
        XCTAssertEqual(placement?.displayIndex, 0)
        XCTAssertEqual(placement?.side, .below)
        XCTAssertEqual(placement?.frame, CGRect(x: 700, y: 674, width: 400, height: 300))
    }

    func testLargeFieldPlacesThePanelInsideIt() {
        let field = CGRect(x: -1100, y: 250, width: 900, height: 600)
        let placement = PlacementEngine.place(request(field: field, mouse: CGPoint(x: 900, y: 500)))
        XCTAssertEqual(placement?.source, .field)
        XCTAssertEqual(placement?.side, .inside)
        XCTAssertEqual(placement?.displayIndex, 1)
        // Centred on the field: X -650, panel centre at 62% of its height.
        XCTAssertEqual(placement?.frame.midX, -650)
        XCTAssertEqual(placement!.frame.midY, 250 + 600 * 0.62, accuracy: 0.001)
    }

    func testWindowSpanningTwoDisplaysUsesTheLargerShare() {
        // 300 pt on the left display, 700 pt on the primary.
        let window = CGRect(x: -300, y: 300, width: 1000, height: 500)
        let placement = PlacementEngine.place(request(window: window, mouse: CGPoint(x: -900, y: 500)))
        XCTAssertEqual(placement?.source, .window)
        XCTAssertEqual(placement?.displayIndex, 0)
        // Inside the window's part of that display: X 0...700.
        XCTAssertEqual(placement?.frame.midX, 350)
        XCTAssertGreaterThanOrEqual(placement!.frame.minX, 12)
    }

    func testMouseDisplayIsUsedOnlyWithoutSourceGeometry() {
        let placement = PlacementEngine.place(request(mouse: CGPoint(x: -640, y: 500)))
        XCTAssertEqual(placement?.source, .mouse)
        XCTAssertEqual(placement?.displayIndex, 1)
        XCTAssertEqual(placement?.frame.midX, -640)
    }

    func testPrimaryDisplayIsTheLastResort() {
        let placement = PlacementEngine.place(request(mouse: CGPoint(x: 9000, y: 9000), displays: [Displays.left, Displays.primary]))
        XCTAssertEqual(placement?.source, .primaryDisplay)
        XCTAssertEqual(placement?.displayIndex, 1)
        XCTAssertEqual(placement?.frame.midX, 960)
    }

    func testPanelAlwaysStaysInsideTheChosenUsableFrame() {
        let lines = [
            CGRect(x: 3, y: 95, width: 0, height: 14),
            CGRect(x: 1915, y: 1040, width: 0, height: 14),
            CGRect(x: -1279, y: 185, width: 0, height: 14),
            CGRect(x: -5, y: 975, width: 0, height: 14),
            CGRect(x: 960, y: 2150, width: 0, height: 14)
        ]
        for line in lines {
            guard let placement = PlacementEngine.place(request(caret: confirmed(line))) else {
                return XCTFail("no placement for \(line)")
            }
            let usable = Displays.all[placement.displayIndex].visibleFrame.insetBy(dx: 12, dy: 12)
            XCTAssertTrue(usable.contains(placement.frame), "\(placement.frame) escapes \(usable) for caret \(line)")
            XCTAssertFalse(placement.frame.insetBy(dx: 1, dy: 1).contains(CGPoint(x: line.midX, y: line.midY)), "panel covers the caret \(line)")
        }
    }

    func testPanelTallerThanTheDisplayKeepsItsTopVisible() {
        let small = DisplayGeometry(frame: CGRect(x: 0, y: 0, width: 800, height: 400), visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 370), isPrimary: true)
        let caret = confirmed(CGRect(x: 200, y: 200, width: 0, height: 16))
        let placement = PlacementEngine.place(request(caret: caret, displays: [small], size: CGSize(width: 400, height: 500)))
        XCTAssertEqual(placement?.side, .clamped)
        XCTAssertEqual(placement?.frame.maxY, 358)
    }

    func testCaretExactlyOnADisplayEdgeBelongsToThatDisplay() {
        let caret = confirmed(CGRect(x: 1920, y: 500, width: 0, height: 16))
        XCTAssertEqual(PlacementEngine.place(request(caret: caret, displays: [Displays.primary]))?.displayIndex, 0)
    }

    func testNoDisplaysOrEmptyPanelYieldNothing() {
        XCTAssertNil(PlacementEngine.place(request(displays: [])))
        XCTAssertNil(PlacementEngine.place(request(size: .zero)))
    }
}
