import XCTest
@testable import CharmsCore

final class FieldAccessTests: XCTestCase {
    private let app = "com.example.chat"

    private func step(hides: Bool = true, identifier: String? = "com.example.chat", allowed: Set<String> = [], declined: Set<String> = [], asked: Set<String> = []) -> FieldAccess.Step {
        FieldAccess.step(bundleIdentifier: identifier, hidesFields: hides, allowed: allowed, declined: declined, asked: asked)
    }

    func testAnApplicationThatShowsItsFieldsIsLeftAlone() {
        XCTAssertEqual(step(hides: false), .leave)
        // Also when the user agreed earlier: there is nothing to switch on.
        XCTAssertEqual(step(hides: false, allowed: [app]), .leave)
    }

    func testAnUnknownApplicationThatHidesItsFieldsIsOfferedOnce() {
        XCTAssertEqual(step(), .offer)
        XCTAssertEqual(step(asked: [app]), .leave)
    }

    func testTheAnswerIsRemembered() {
        XCTAssertEqual(step(allowed: [app]), .request)
        XCTAssertEqual(step(declined: [app]), .leave)
        // Having been asked this run does not undo an agreement.
        XCTAssertEqual(step(allowed: [app], asked: [app]), .request)
    }

    func testAnswersBelongToOneApplication() {
        XCTAssertEqual(step(allowed: ["com.example.other"], declined: ["com.example.third"], asked: ["com.example.fourth"]), .offer)
    }

    func testWithoutAnIdentifierNothingIsOffered() {
        XCTAssertEqual(step(identifier: nil), .leave)
        XCTAssertEqual(step(identifier: ""), .leave)
    }

    func testRecordingKeepsAnApplicationInOneListOnly() {
        var preferences = Preferences()
        FieldAccess.record(.decline(remember: true), for: app, in: &preferences)
        XCTAssertEqual(preferences.fieldAccessDeclined, [app])
        XCTAssertEqual(preferences.fieldAccessApplications, [])

        FieldAccess.record(.turnOn, for: app, in: &preferences)
        XCTAssertEqual(preferences.fieldAccessApplications, [app])
        XCTAssertEqual(preferences.fieldAccessDeclined, [])

        FieldAccess.record(.decline(remember: false), for: app, in: &preferences)
        XCTAssertEqual(preferences.fieldAccessApplications, [])
        XCTAssertEqual(preferences.fieldAccessDeclined, [])
    }

    func testForgettingAnswersAsksAgain() {
        var preferences = Preferences(fieldAccessApplications: [app], fieldAccessDeclined: ["com.example.other"])
        FieldAccess.forgetAnswers(in: &preferences)
        XCTAssertEqual(step(allowed: preferences.fieldAccessApplications, declined: preferences.fieldAccessDeclined), .offer)
    }

    func testStoredPreferencesWithoutTheListsStillDecode() {
        let old = Data(#"{"typedTriggerEnabled": true}"#.utf8)
        let preferences = Preferences.decoded(from: old)
        XCTAssertTrue(preferences.typedTriggerEnabled)
        XCTAssertEqual(preferences.fieldAccessApplications, [])
        XCTAssertEqual(preferences.fieldAccessDeclined, [])

        var changed = preferences
        changed.fieldAccessApplications = [app]
        XCTAssertEqual(Preferences.decoded(from: changed.encoded()).fieldAccessApplications, [app])
    }
}
