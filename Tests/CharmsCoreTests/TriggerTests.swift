import XCTest
@testable import CharmsCore

final class TriggerRecognizerTests: XCTestCase {
    private func key(_ characters: String, at time: TimeInterval, pid: Int32 = 100, isRepeat: Bool = false, isShortcut: Bool = false) -> KeyObservation {
        KeyObservation(characters: characters, isRepeat: isRepeat, isShortcut: isShortcut, processID: pid, timestamp: time)
    }

    func testTwoColonsTrigger() {
        var recognizer = TriggerRecognizer()
        XCTAssertEqual(recognizer.observe(key(":", at: 1.0)), .candidate)
        XCTAssertEqual(recognizer.observe(key(":", at: 1.2)), .triggered(processID: 100))
        XCTAssertFalse(recognizer.hasCandidate)
    }

    func testColonsMoreThanOneSecondApartDoNotTrigger() {
        var recognizer = TriggerRecognizer()
        XCTAssertEqual(recognizer.observe(key(":", at: 1.0)), .candidate)
        // The late colon starts a new candidate instead of completing the old one.
        XCTAssertEqual(recognizer.observe(key(":", at: 2.5)), .candidate)
        XCTAssertEqual(recognizer.observe(key(":", at: 2.6)), .triggered(processID: 100))
    }

    func testAnotherKeyBetweenColonsCancelsTheCandidate() {
        var recognizer = TriggerRecognizer()
        _ = recognizer.observe(key(":", at: 1.0))
        XCTAssertEqual(recognizer.observe(key("a", at: 1.1)), .nothing)
        XCTAssertEqual(recognizer.observe(key(":", at: 1.2)), .candidate)
    }

    func testColonsInDifferentApplicationsDoNotCombine() {
        var recognizer = TriggerRecognizer()
        _ = recognizer.observe(key(":", at: 1.0, pid: 100))
        XCTAssertEqual(recognizer.observe(key(":", at: 1.1, pid: 200)), .candidate)
    }

    func testHeldColonKeyDoesNotTrigger() {
        var recognizer = TriggerRecognizer()
        _ = recognizer.observe(key(":", at: 1.0))
        XCTAssertEqual(recognizer.observe(key(":", at: 1.5, isRepeat: true)), .nothing)
        XCTAssertFalse(recognizer.hasCandidate)
    }

    func testShortcutWithColonIsNotACandidate() {
        var recognizer = TriggerRecognizer()
        XCTAssertEqual(recognizer.observe(key(":", at: 1.0, isShortcut: true)), .nothing)
        XCTAssertFalse(recognizer.hasCandidate)
    }

    func testResetForgetsTheFirstColon() {
        var recognizer = TriggerRecognizer()
        _ = recognizer.observe(key(":", at: 1.0))
        recognizer.reset()
        XCTAssertEqual(recognizer.observe(key(":", at: 1.1)), .candidate)
    }

    func testThirdColonDoesNotPairWithTheSecond() {
        var recognizer = TriggerRecognizer()
        _ = recognizer.observe(key(":", at: 1.0))
        XCTAssertEqual(recognizer.observe(key(":", at: 1.1)), .triggered(processID: 100))
        // After a trigger everything is forgotten, so `:::` needs two more.
        XCTAssertEqual(recognizer.observe(key(":", at: 1.2)), .candidate)
    }

    func testBoundaryAfterVisibleTextIsReported() {
        var recognizer = TriggerRecognizer()
        for (offset, character) in ["s", "t", "d"].enumerated() {
            _ = recognizer.observe(key(character, at: 1.0 + Double(offset) * 0.1))
        }
        _ = recognizer.observe(key(":", at: 1.4))
        XCTAssertEqual(recognizer.observe(key(":", at: 1.5)), .triggered(processID: 100))
        XCTAssertEqual(recognizer.lastBoundary, .text)
    }

    func testBoundaryAfterSpaceIsWhitespace() {
        var recognizer = TriggerRecognizer()
        _ = recognizer.observe(key("a", at: 1.0))
        _ = recognizer.observe(key(" ", at: 1.1))
        _ = recognizer.observe(key(":", at: 1.2))
        _ = recognizer.observe(key(":", at: 1.3))
        XCTAssertEqual(recognizer.lastBoundary, .whitespace)
    }

    func testBoundaryIsUnknownAfterAnArrowKey() {
        var recognizer = TriggerRecognizer()
        _ = recognizer.observe(key("a", at: 1.0))
        // Left arrow, as AppKit reports it.
        _ = recognizer.observe(key("\u{F702}", at: 1.1))
        _ = recognizer.observe(key(":", at: 1.2))
        _ = recognizer.observe(key(":", at: 1.3))
        XCTAssertEqual(recognizer.lastBoundary, .unknown)
    }

    func testKeyObservationClassifiesText() {
        XCTAssertTrue(key("a", at: 0).isText)
        XCTAssertTrue(key(" ", at: 0).isText)
        XCTAssertTrue(key("é", at: 0).isText)
        XCTAssertFalse(key("", at: 0).isText)
        XCTAssertFalse(key("\u{7F}", at: 0).isText, "Delete")
        XCTAssertFalse(key("\r", at: 0).isText, "Return")
        XCTAssertFalse(key("\u{F700}", at: 0).isText, "Up arrow")
        XCTAssertFalse(key("v", at: 0, isShortcut: true).isText)
    }
}

final class TriggerHandoffTests: XCTestCase {
    private func key(_ characters: String, isRepeat: Bool = false, isShortcut: Bool = false) -> KeyObservation {
        KeyObservation(characters: characters, isRepeat: isRepeat, isShortcut: isShortcut, processID: 1, timestamp: 0)
    }

    private func handoff(_ typed: String) -> TriggerHandoff {
        var handoff = TriggerHandoff()
        for character in typed {
            handoff.sourceReceived(key(String(character)))
        }
        return handoff
    }

    func testNoPrefixExpectsOnlyTheMarker() {
        let handoff = TriggerHandoff()
        XCTAssertEqual(handoff.expectedText, "::")
        XCTAssertEqual(handoff.verify(caretLocation: 2, textBeforeCaret: "::", precedingCharacter: nil), .verified(location: 0, length: 2))
    }

    func testPrefixTypedIntoTheSourceBecomesStartOfQuery() {
        let handoff = handoff("arr")
        XCTAssertEqual(handoff.expectedText, "::arr")
        XCTAssertEqual(handoff.query(pickerText: "ow"), "arrow")
        XCTAssertEqual(handoff.verify(caretLocation: 11, textBeforeCaret: "::arr", precedingCharacter: " "), .verified(location: 6, length: 5))
    }

    func testEverySplitOfTheQueryYieldsTheSameQuery() {
        let word = "arrow"
        for split in 0...word.count {
            let sourcePart = String(word.prefix(split))
            let pickerPart = String(word.dropFirst(split))
            XCTAssertEqual(handoff(sourcePart).query(pickerText: pickerPart), word, "split at \(split)")
        }
    }

    func testRangeIsMeasuredInUTF16UnitsAfterAnEmoji() {
        // "👍🏽 ::ar" - the emoji is four UTF-16 units, so the marker starts at 5.
        let handoff = handoff("ar")
        let text = "👍🏽 ::ar"
        XCTAssertEqual(text.utf16.count, 9)
        XCTAssertEqual(handoff.verify(caretLocation: 9, textBeforeCaret: "::ar", precedingCharacter: " "), .verified(location: 5, length: 4))
    }

    func testMarkerAfterVisibleTextIsNotABoundary() {
        let handoff = TriggerHandoff()
        XCTAssertEqual(handoff.verify(caretLocation: 5, textBeforeCaret: "::", precedingCharacter: "d"), .notAtBoundary)
        XCTAssertEqual(handoff.verify(caretLocation: 5, textBeforeCaret: "::", precedingCharacter: "["), .notAtBoundary)
    }

    func testMarkerAfterNewlineOrTabIsABoundary() {
        let handoff = TriggerHandoff()
        XCTAssertEqual(handoff.verify(caretLocation: 3, textBeforeCaret: "::", precedingCharacter: "\n"), .verified(location: 1, length: 2))
        XCTAssertEqual(handoff.verify(caretLocation: 3, textBeforeCaret: "::", precedingCharacter: "\t"), .verified(location: 1, length: 2))
    }

    func testSourceStillCatchingUpIsIncomplete() {
        let handoff = handoff("arr")
        XCTAssertEqual(handoff.verify(caretLocation: 3, textBeforeCaret: "x ::", precedingCharacter: nil), .incomplete)
        XCTAssertEqual(handoff.verify(caretLocation: 4, textBeforeCaret: " ::ar", precedingCharacter: nil), .incomplete)
        XCTAssertEqual(handoff.verify(caretLocation: 0, textBeforeCaret: "", precedingCharacter: nil), .incomplete)
    }

    func testDifferentSourceTextIsAMismatch() {
        let handoff = handoff("arr")
        XCTAssertEqual(handoff.verify(caretLocation: 5, textBeforeCaret: "::axr", precedingCharacter: nil), .mismatch)
        XCTAssertEqual(handoff.verify(caretLocation: 5, textBeforeCaret: "hello", precedingCharacter: nil), .mismatch)
    }

    func testAutocorrectedSourceTextIsAMismatch() {
        // The source replaced what was typed; nothing may be removed.
        let handoff = handoff("teh")
        XCTAssertEqual(handoff.verify(caretLocation: 5, textBeforeCaret: "::the", precedingCharacter: nil), .mismatch)
    }

    func testCanonicallyEquivalentTextIsStillAMismatch() {
        // é typed as one scalar; the source holds e plus a combining accent.
        let handoff = handoff("\u{E9}")
        XCTAssertEqual(handoff.verify(caretLocation: 4, textBeforeCaret: "::e\u{301}", precedingCharacter: nil), .mismatch)
    }

    func testEditingKeyInTheSourceInvalidatesTheHandoff() {
        var handoff = handoff("ar")
        handoff.sourceReceived(key("\u{7F}"))
        XCTAssertEqual(handoff.problem, .sourceEdited)
        XCTAssertEqual(handoff.verify(caretLocation: 4, textBeforeCaret: "::ar", precedingCharacter: nil), .mismatch)
    }

    func testReturnInTheSourceInvalidatesTheHandoff() {
        var handoff = handoff("ar")
        handoff.sourceReceived(key("\r"))
        XCTAssertEqual(handoff.problem, .sourceEdited)
    }

    func testShortcutInTheSourceInvalidatesTheHandoff() {
        var handoff = TriggerHandoff()
        handoff.sourceReceived(key("v", isShortcut: true))
        XCTAssertEqual(handoff.problem, .sourceEdited)
    }

    func testSpaceAfterTheMarkerMeansOrdinaryText() {
        var handoff = TriggerHandoff()
        handoff.sourceReceived(key(" "))
        XCTAssertEqual(handoff.problem, .whitespaceAfterMarker)
    }

    func testPrefixIsBounded() {
        var handoff = TriggerHandoff()
        for _ in 0..<TriggerHandoff.maximumPrefixUTF16Length {
            handoff.sourceReceived(key("a"))
        }
        XCTAssertNil(handoff.problem)
        handoff.sourceReceived(key("a"))
        XCTAssertEqual(handoff.problem, .prefixTooLong)
        XCTAssertEqual(handoff.sourcePrefix.utf16.count, TriggerHandoff.maximumPrefixUTF16Length)
    }

    func testCaretBeforeTheExpectedTextIsAMismatch() {
        let handoff = handoff("ar")
        XCTAssertEqual(handoff.verify(caretLocation: 2, textBeforeCaret: "::ar", precedingCharacter: nil), .mismatch)
    }
}

final class TriggerEligibilityTests: XCTestCase {
    private func eligibility(enabled: Bool = true, accessibility: Bool = true, secure: Bool = false, session: Bool = false, inputMethod: Bool = false) -> TriggerEligibility {
        TriggerEligibility(isEnabled: enabled, hasAccessibility: accessibility, isSecureInputActive: secure, isSessionActive: session, isInputMethodActive: inputMethod)
    }

    func testObserverIsInstalledOnlyWhenEnabledAndTrusted() {
        XCTAssertNil(eligibility().observerBlocker)
        XCTAssertEqual(eligibility(enabled: false).observerBlocker, .disabled)
        XCTAssertEqual(eligibility(accessibility: false).observerBlocker, .accessibilityMissing)
    }

    func testTransientConditionsBlockAMarkerButNotTheObserver() {
        let exclusions: Set<String> = []
        XCTAssertNil(eligibility(secure: true).observerBlocker)
        XCTAssertEqual(eligibility(secure: true).blocker(forBundleIdentifier: "a.b", ownBundleIdentifier: "ch.lkmc.Charms", exclusions: exclusions), .secureInput)
        XCTAssertEqual(eligibility(session: true).blocker(forBundleIdentifier: "a.b", ownBundleIdentifier: "ch.lkmc.Charms", exclusions: exclusions), .sessionActive)
        XCTAssertEqual(eligibility(inputMethod: true).blocker(forBundleIdentifier: "a.b", ownBundleIdentifier: "ch.lkmc.Charms", exclusions: exclusions), .inputMethodActive)
    }

    func testExcludedAndOwnApplicationsAreBlocked() {
        let exclusions: Set<String> = ["com.apple.Terminal", "com.jetbrains.*"]
        let eligible = eligibility()
        XCTAssertEqual(eligible.blocker(forBundleIdentifier: "com.apple.Terminal", ownBundleIdentifier: "ch.lkmc.Charms", exclusions: exclusions), .excludedApplication)
        XCTAssertEqual(eligible.blocker(forBundleIdentifier: "com.jetbrains.intellij", ownBundleIdentifier: "ch.lkmc.Charms", exclusions: exclusions), .excludedApplication)
        XCTAssertEqual(eligible.blocker(forBundleIdentifier: "ch.lkmc.Charms", ownBundleIdentifier: "ch.lkmc.Charms", exclusions: exclusions), .ownApplication)
        XCTAssertNil(eligible.blocker(forBundleIdentifier: "com.apple.TextEdit", ownBundleIdentifier: "ch.lkmc.Charms", exclusions: exclusions))
    }
}
