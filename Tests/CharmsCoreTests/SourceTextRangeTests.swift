import XCTest
@testable import CharmsCore

final class SourceTextRangeTests: XCTestCase {
    func testOrdinaryRangesAreAccepted() {
        XCTAssertEqual(SourceTextRange(location: 0, length: 0)?.end, 0)
        XCTAssertEqual(SourceTextRange(location: 5, length: 3)?.end, 8)
    }

    func testNegativeValuesAreRejected() {
        XCTAssertNil(SourceTextRange(location: -1, length: 0))
        XCTAssertNil(SourceTextRange(location: 0, length: -1))
        XCTAssertNil(SourceTextRange(location: Int.min, length: Int.min))
    }

    func testRangeWhoseEndCannotBeComputedIsRejected() {
        // An application may report anything. Adding these two would trap.
        XCTAssertNil(SourceTextRange(location: Int.max, length: 1))
        XCTAssertNil(SourceTextRange(location: Int.max - 2, length: Int.max))
    }

    func testLargestRepresentableRangeIsStillARange() {
        XCTAssertEqual(SourceTextRange(location: Int.max, length: 0)?.end, Int.max)
        XCTAssertEqual(SourceTextRange(location: 0, length: Int.max)?.end, Int.max)
    }
}
