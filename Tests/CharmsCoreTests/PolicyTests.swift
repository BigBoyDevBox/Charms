import XCTest
@testable import CharmsCore

final class KeyComboTests: XCTestCase {
    func testStandardShortcutIsControlP() {
        XCTAssertEqual(KeyCombo.standard.keyCode, 35)
        XCTAssertEqual(KeyCombo.standard.modifiers, .control)
        XCTAssertEqual(KeyCombo.standard.displayString(keyCharacter: "p"), "⌃P")
        XCTAssertNil(KeyCombo.standard.problem(keyCharacter: "p"))
    }

    func testModifierSymbolsFollowMenuOrder() {
        let all: KeyCombo.Modifiers = [.command, .shift, .option, .control]
        XCTAssertEqual(all.symbols, "⌃⌥⇧⌘")
    }

    func testPlainAndShiftOnlyKeysAreRejected() {
        XCTAssertEqual(KeyCombo(keyCode: 35, modifiers: []).problem(keyCharacter: "p"), .needsModifier)
        XCTAssertEqual(KeyCombo(keyCode: 35, modifiers: .shift).problem(keyCharacter: "p"), .needsModifier)
    }

    func testFunctionKeysNeedNoModifier() {
        let f5 = KeyCombo(keyCode: 96, modifiers: [])
        XCTAssertNil(f5.problem(keyCharacter: nil))
        XCTAssertEqual(f5.displayString(keyCharacter: nil), "F5")
    }

    func testEditingCommandsAreReservedByCharacterNotPosition() {
        // On a Swiss German keyboard position 6 types "y" and position 16
        // types "z": Undo is Command with position 16.
        XCTAssertEqual(KeyCombo(keyCode: 16, modifiers: .command).problem(keyCharacter: "z"), .reserved)
        XCTAssertNil(KeyCombo(keyCode: 6, modifiers: .command).problem(keyCharacter: "y"))
        XCTAssertEqual(KeyCombo(keyCode: 9, modifiers: .command).problem(keyCharacter: "v"), .reserved)
        XCTAssertEqual(KeyCombo(keyCode: 6, modifiers: [.command, .shift]).problem(keyCharacter: "Z"), .reserved)
    }

    func testReservedCommandsWithMoreModifiersAreAllowed() {
        XCTAssertNil(KeyCombo(keyCode: 9, modifiers: [.command, .option]).problem(keyCharacter: "v"))
        XCTAssertNil(KeyCombo(keyCode: 9, modifiers: [.control]).problem(keyCharacter: "v"))
    }

    func testSystemSwitcherCombinationsAreReserved() {
        XCTAssertEqual(KeyCombo(keyCode: 48, modifiers: .command).problem(keyCharacter: "\t"), .reserved)
        XCTAssertEqual(KeyCombo(keyCode: 49, modifiers: .command).problem(keyCharacter: " "), .reserved)
        XCTAssertEqual(KeyCombo(keyCode: 53, modifiers: [.command, .option]).problem(keyCharacter: nil), .reserved)
    }

    func testLabelsForSpecialKeys() {
        XCTAssertEqual(KeyCombo(keyCode: 49, modifiers: [.control, .option]).displayString(keyCharacter: " "), "⌃⌥Space")
        XCTAssertEqual(KeyCombo(keyCode: 36, modifiers: .command).displayString(keyCharacter: "\r"), "⌘↩")
        XCTAssertEqual(KeyCombo(keyCode: 200, modifiers: .command).displayString(keyCharacter: nil), "⌘Key 200")
        XCTAssertEqual(KeyCombo(keyCode: 41, modifiers: .control).displayString(keyCharacter: "ö"), "⌃Ö")
    }

    func testCodableRoundTrip() throws {
        let combo = KeyCombo(keyCode: 12, modifiers: [.control, .shift])
        let data = try JSONEncoder().encode(combo)
        XCTAssertEqual(try JSONDecoder().decode(KeyCombo.self, from: data), combo)
    }
}

final class InsertionPolicyTests: XCTestCase {
    func testKeyboardEventsAreTheDefaultBackend() {
        XCTAssertEqual(InsertionPolicy.backend(forBundleIdentifier: "com.apple.TextEdit", pasteApplications: []), .unicodeEvents)
        XCTAssertEqual(InsertionPolicy.backend(forBundleIdentifier: nil, pasteApplications: ["a.b"]), .unicodeEvents)
    }

    func testPasteIsUsedOnlyForListedApplications() {
        let list: Set<String> = ["com.example.Stubborn", "org.vendor.*"]
        XCTAssertEqual(InsertionPolicy.backend(forBundleIdentifier: "com.example.Stubborn", pasteApplications: list), .paste)
        XCTAssertEqual(InsertionPolicy.backend(forBundleIdentifier: "org.vendor.editor", pasteApplications: list), .paste)
        XCTAssertEqual(InsertionPolicy.backend(forBundleIdentifier: "org.vendorx.editor", pasteApplications: list), .unicodeEvents)
        XCTAssertEqual(InsertionPolicy.backend(forBundleIdentifier: "com.example.Other", pasteApplications: list), .unicodeEvents)
    }

    func testCatalogueStringsTravelInOneEvent() {
        for text in ["→", "😀", "👍🏽", "👩‍💻", "🇨🇭", "#️⃣", "❤️", "🏴󠁧󠁢󠁳󠁣󠁴󠁿", "🧑🏻‍❤️‍💋‍🧑🏼"] {
            let payloads = InsertionPolicy.eventPayloads(for: text)
            XCTAssertEqual(payloads.count, 1, text)
            XCTAssertEqual(payloads.first, Array(text.utf16), text)
        }
    }

    func testLongTextIsSplitBetweenCharactersOnly() {
        let family = "👨‍👩‍👧‍👦"
        XCTAssertEqual(family.utf16.count, 11)
        let text = String(repeating: family, count: 4)
        let payloads = InsertionPolicy.eventPayloads(for: text, limit: 20)
        XCTAssertEqual(payloads.count, 4)
        for payload in payloads {
            XCTAssertEqual(payload, Array(family.utf16))
        }
        XCTAssertEqual(payloads.flatMap { $0 }, Array(text.utf16))
    }

    func testACharacterLongerThanTheLimitStaysWhole() {
        let flag = "🏴󠁧󠁢󠁳󠁣󠁴󠁿"
        XCTAssertEqual(flag.utf16.count, 14)
        XCTAssertEqual(InsertionPolicy.eventPayloads(for: flag, limit: 4), [Array(flag.utf16)])
    }

    func testEmptyTextHasNoPayload() {
        XCTAssertTrue(InsertionPolicy.eventPayloads(for: "").isEmpty)
    }
}

final class ReleaseGateTests: XCTestCase {
    private let held = ReleaseGate.Inputs(modifiersDown: false, commitKeyDown: true, mouseButtonDown: false)
    private let free = ReleaseGate.Inputs(modifiersDown: false, commitKeyDown: false, mouseButtonDown: false)

    func testWaitsWhileTheCommitKeyIsDown() {
        let gate = ReleaseGate(start: 10)
        XCTAssertEqual(gate.evaluate(held, now: 10.2), .wait)
        XCTAssertEqual(gate.evaluate(free, now: 10.3), .released)
    }

    func testWaitsForModifiersAndMouseButton() {
        let gate = ReleaseGate(start: 0)
        XCTAssertEqual(gate.evaluate(.init(modifiersDown: true, commitKeyDown: false, mouseButtonDown: false), now: 0.1), .wait)
        XCTAssertEqual(gate.evaluate(.init(modifiersDown: false, commitKeyDown: false, mouseButtonDown: true), now: 0.1), .wait)
    }

    func testExpiresAfterTheDeadline() {
        let gate = ReleaseGate(start: 10)
        XCTAssertEqual(gate.evaluate(held, now: 10.99), .wait)
        XCTAssertEqual(gate.evaluate(held, now: 11.0), .expired)
    }

    func testReleaseAtTheDeadlineStillCounts() {
        let gate = ReleaseGate(start: 10)
        XCTAssertEqual(gate.evaluate(free, now: 12), .released)
    }
}

final class TargetCheckTests: XCTestCase {
    private func check(trusted: Bool = true, secureInput: Bool = false, sameProcess: Bool = true, frontmost: Bool = true, sameElement: Bool = true, secureField: Bool = false, selection: Bool? = true) -> TargetCheck {
        TargetCheck(accessibilityTrusted: trusted, secureInputActive: secureInput, sameProcess: sameProcess, processIsFrontmost: frontmost, sameElement: sameElement, elementIsSecure: secureField, selectionUnchanged: selection)
    }

    func testUnchangedTargetIsValid() {
        XCTAssertNil(check().failure)
        XCTAssertEqual(check().validation, .valid)
    }

    func testUnreadableSelectionDoesNotBlock() {
        XCTAssertEqual(check(selection: nil).validation, .valid)
    }

    func testEachChangeBlocksInsertion() {
        XCTAssertEqual(check(trusted: false).failure, .accessibilityRevoked)
        XCTAssertEqual(check(secureInput: true).failure, .secureInput)
        XCTAssertEqual(check(sameProcess: false).failure, .processGone)
        XCTAssertEqual(check(frontmost: false).failure, .processNotFrontmost)
        XCTAssertEqual(check(sameElement: false).failure, .focusMoved)
        XCTAssertEqual(check(secureField: true).failure, .secureField)
        XCTAssertEqual(check(selection: false).failure, .selectionChanged)
    }

    func testAGoneContextIsInvalidAndAMovedFocusIsCopyOnly() {
        XCTAssertEqual(check(sameProcess: false).validation, .invalid)
        XCTAssertEqual(check(frontmost: false).validation, .invalid)
        XCTAssertEqual(check(sameElement: false).validation, .copyOnly)
        XCTAssertEqual(check(secureInput: true).validation, .copyOnly)
        XCTAssertEqual(check(selection: false).validation, .copyOnly)
    }
}

final class ClipboardRestoreGuardTests: XCTestCase {
    func testRestoresWhenNothingElseWasCopied() {
        var clipboard = ClipboardRestoreGuard()
        XCTAssertTrue(clipboard.begin(session: SessionID(1), changeCountAfterWrite: 42))
        XCTAssertTrue(clipboard.resolve(session: SessionID(1), currentChangeCount: 42))
        XCTAssertTrue(clipboard.canBegin)
    }

    func testNewerUserCopyIsNeverOverwritten() {
        var clipboard = ClipboardRestoreGuard()
        clipboard.begin(session: SessionID(1), changeCountAfterWrite: 42)
        XCTAssertFalse(clipboard.resolve(session: SessionID(1), currentChangeCount: 43))
        XCTAssertTrue(clipboard.canBegin)
    }

    func testRestoresOnlyOnce() {
        var clipboard = ClipboardRestoreGuard()
        clipboard.begin(session: SessionID(1), changeCountAfterWrite: 42)
        XCTAssertTrue(clipboard.resolve(session: SessionID(1), currentChangeCount: 42))
        XCTAssertFalse(clipboard.resolve(session: SessionID(1), currentChangeCount: 42))
    }

    func testSecondTransactionCannotStartWhileOneIsPending() {
        var clipboard = ClipboardRestoreGuard()
        XCTAssertTrue(clipboard.begin(session: SessionID(1), changeCountAfterWrite: 42))
        XCTAssertFalse(clipboard.canBegin)
        XCTAssertFalse(clipboard.begin(session: SessionID(2), changeCountAfterWrite: 44))
        XCTAssertEqual(clipboard.pending?.session, SessionID(1))
    }

    func testAnotherSessionCannotResolveTheTransaction() {
        var clipboard = ClipboardRestoreGuard()
        clipboard.begin(session: SessionID(1), changeCountAfterWrite: 42)
        XCTAssertFalse(clipboard.resolve(session: SessionID(2), currentChangeCount: 42))
        XCTAssertNotNil(clipboard.pending)
    }

    func testAbandonDropsTheTransactionWithoutRestoring() {
        var clipboard = ClipboardRestoreGuard()
        clipboard.begin(session: SessionID(1), changeCountAfterWrite: 42)
        clipboard.abandon()
        XCTAssertTrue(clipboard.canBegin)
        XCTAssertFalse(clipboard.resolve(session: SessionID(1), currentChangeCount: 42))
    }
}

final class PreferencesTests: XCTestCase {
    func testDefaults() {
        let preferences = Preferences()
        XCTAssertEqual(preferences.shortcut, .standard)
        XCTAssertFalse(preferences.typedTriggerEnabled, "the typed trigger is opt-in")
        XCTAssertTrue(preferences.pasteApplications.isEmpty)
        XCTAssertTrue(preferences.shortcutPassThrough.isEmpty, "the shortcut is global unless the user says otherwise")
        XCTAssertTrue(preferences.triggerExclusions.contains("com.apple.Terminal"))
        XCTAssertFalse(preferences.hasCompletedOnboarding)
    }

    func testRoundTrip() {
        var preferences = Preferences()
        preferences.shortcut = KeyCombo(keyCode: 40, modifiers: [.control, .option])
        preferences.skinTone = .mediumDark
        preferences.typedTriggerEnabled = true
        preferences.triggerExclusions = ["a.b"]
        preferences.pasteApplications = ["c.d"]
        preferences.shortcutPassThrough = ["e.f"]
        preferences.hasCompletedOnboarding = true
        XCTAssertEqual(Preferences.decoded(from: preferences.encoded()), preferences)
    }

    func testMissingFieldsTakeDefaultsAndKnownFieldsSurvive() {
        let data = Data(#"{"typedTriggerEnabled":true,"skinTone":"dark"}"#.utf8)
        let preferences = Preferences.decoded(from: data)
        XCTAssertTrue(preferences.typedTriggerEnabled)
        XCTAssertEqual(preferences.skinTone, .dark)
        XCTAssertEqual(preferences.shortcut, .standard)
        XCTAssertEqual(preferences.triggerExclusions, DefaultApplications.triggerExclusions)
    }

    func testUnreadableFieldDoesNotLoseTheOthers() {
        let data = Data(#"{"typedTriggerEnabled":true,"skinTone":"purple","shortcut":"nonsense"}"#.utf8)
        let preferences = Preferences.decoded(from: data)
        XCTAssertTrue(preferences.typedTriggerEnabled)
        XCTAssertEqual(preferences.skinTone, .none)
        XCTAssertEqual(preferences.shortcut, .standard)
    }

    func testGarbageYieldsDefaults() {
        XCTAssertEqual(Preferences.decoded(from: Data("not json".utf8)), Preferences())
        XCTAssertEqual(Preferences.decoded(from: nil), Preferences())
    }

    func testTurningTheTypedTriggerOffSurvivesEncoding() {
        var preferences = Preferences()
        preferences.typedTriggerEnabled = true
        XCTAssertTrue(Preferences.decoded(from: preferences.encoded()).typedTriggerEnabled)
        preferences.typedTriggerEnabled = false
        XCTAssertFalse(Preferences.decoded(from: preferences.encoded()).typedTriggerEnabled)
    }
}

final class BundlePatternTests: XCTestCase {
    func testExactAndPrefixPatterns() {
        let patterns: Set<String> = ["com.apple.Terminal", "com.jetbrains.*"]
        XCTAssertTrue(BundlePattern.matches("com.apple.Terminal", in: patterns))
        XCTAssertFalse(BundlePattern.matches("com.apple.TerminalX", in: patterns))
        XCTAssertTrue(BundlePattern.matches("com.jetbrains.pycharm", in: patterns))
        XCTAssertFalse(BundlePattern.matches("com.jetbrainsx.pycharm", in: patterns))
        XCTAssertFalse(BundlePattern.matches("com.jetbrains", in: patterns))
    }
}

final class GridNavigatorTests: XCTestCase {
    private func position(_ section: Int, _ index: Int) -> GridMove {
        .position(GridPosition(section: section, index: index))
    }

    func testNoSelectionLandsOnTheFirstCell() {
        let grid = GridNavigator(sections: [0, 5], columns: 8)
        XCTAssertEqual(grid.move(from: nil, .down), position(1, 0))
        XCTAssertEqual(grid.move(from: nil, .right), position(1, 0))
    }

    func testEmptyGridHasNoMoves() {
        let grid = GridNavigator(sections: [0, 0], columns: 8)
        XCTAssertTrue(grid.isEmpty)
        XCTAssertNil(grid.move(from: nil, .down))
        XCTAssertNil(grid.first)
    }

    func testRightWalksInReadingOrderAndStopsAtTheLastCell() {
        let grid = GridNavigator(sections: [10], columns: 8)
        XCTAssertEqual(grid.move(from: GridPosition(section: 0, index: 7), .right), position(0, 8))
        XCTAssertEqual(grid.move(from: GridPosition(section: 0, index: 9), .right), position(0, 9))
    }

    func testLeftFromARowStartGoesToThePreviousRowsEnd() {
        let grid = GridNavigator(sections: [10], columns: 8)
        XCTAssertEqual(grid.move(from: GridPosition(section: 0, index: 8), .left), position(0, 7))
        XCTAssertEqual(grid.move(from: GridPosition(section: 0, index: 0), .left), position(0, 0))
    }

    func testDownClampsIntoAShortLastRow() {
        // Rows: 0-7, 8-9.
        let grid = GridNavigator(sections: [10], columns: 8)
        XCTAssertEqual(grid.move(from: GridPosition(section: 0, index: 1), .down), position(0, 9))
        XCTAssertEqual(grid.move(from: GridPosition(section: 0, index: 5), .down), position(0, 9))
        XCTAssertEqual(grid.move(from: GridPosition(section: 0, index: 0), .down), position(0, 8))
    }

    func testDownFromTheLastRowStays() {
        let grid = GridNavigator(sections: [10], columns: 8)
        XCTAssertEqual(grid.move(from: GridPosition(section: 0, index: 9), .down), position(0, 9))
    }

    func testOneCellLastRowAnswersUpAndDown() {
        // Rows: 0-7, 8.
        let grid = GridNavigator(sections: [9], columns: 8)
        XCTAssertEqual(grid.move(from: GridPosition(section: 0, index: 6), .down), position(0, 8))
        XCTAssertEqual(grid.move(from: GridPosition(section: 0, index: 8), .up), position(0, 0))
        XCTAssertEqual(grid.move(from: GridPosition(section: 0, index: 8), .down), position(0, 8))
    }

    func testUpFromTheFirstRowReturnsToSearch() {
        let grid = GridNavigator(sections: [10], columns: 8)
        XCTAssertEqual(grid.move(from: GridPosition(section: 0, index: 3), .up), .searchField)
        XCTAssertEqual(grid.move(from: GridPosition(section: 0, index: 9), .up), position(0, 1))
    }

    func testMovingBetweenSectionsKeepsTheColumn() {
        // Favourites: 8 cells in one row. Recents: 12 cells, rows 0-7 and 8-11.
        let grid = GridNavigator(sections: [8, 12], columns: 8)
        XCTAssertEqual(grid.move(from: GridPosition(section: 0, index: 3), .down), position(1, 3))
        XCTAssertEqual(grid.move(from: GridPosition(section: 1, index: 3), .up), position(0, 3))
        XCTAssertEqual(grid.move(from: GridPosition(section: 0, index: 7), .right), position(1, 0))
        XCTAssertEqual(grid.move(from: GridPosition(section: 1, index: 0), .left), position(0, 7))
    }

    func testMovingUpIntoAShortSectionClampsToItsLastCell() {
        // Favourites: 3 cells. Recents: 8 cells.
        let grid = GridNavigator(sections: [3, 8], columns: 8)
        XCTAssertEqual(grid.move(from: GridPosition(section: 1, index: 6), .up), position(0, 2))
        XCTAssertEqual(grid.move(from: GridPosition(section: 0, index: 2), .down), position(1, 2))
    }

    func testUpIntoAMultiRowSectionLandsOnItsLastRow() {
        // First section rows: 0-7, 8-10.
        let grid = GridNavigator(sections: [11, 4], columns: 8)
        XCTAssertEqual(grid.move(from: GridPosition(section: 1, index: 1), .up), position(0, 9))
        XCTAssertEqual(grid.move(from: GridPosition(section: 1, index: 3), .up), position(0, 10))
    }

    func testEmptySectionsAreSkipped() {
        let grid = GridNavigator(sections: [4, 0, 4], columns: 8)
        XCTAssertEqual(grid.move(from: GridPosition(section: 0, index: 3), .right), position(2, 0))
        XCTAssertEqual(grid.move(from: GridPosition(section: 2, index: 1), .up), position(0, 1))
    }

    func testStaleSelectionRestartsAtTheFirstCell() {
        let grid = GridNavigator(sections: [4], columns: 8)
        XCTAssertEqual(grid.move(from: GridPosition(section: 0, index: 9), .right), position(0, 0))
        XCTAssertEqual(grid.move(from: GridPosition(section: 3, index: 0), .left), position(0, 0))
    }

    func testColumnCountIsAtLeastOne() {
        let grid = GridNavigator(sections: [3], columns: 0)
        XCTAssertEqual(grid.columns, 1)
        XCTAssertEqual(grid.move(from: GridPosition(section: 0, index: 0), .down), position(0, 1))
    }
}

final class DiagnosticsLogTests: XCTestCase {
    func testRecordsAndExportsEntries() {
        let log = DiagnosticsLog(now: { Date(timeIntervalSince1970: 0) })
        log.record(.placement, "placed-caret", application: "com.apple.TextEdit", milliseconds: 8.25)
        log.record(.session, "outcome-dispatched")
        let text = log.export(header: [("version", "0.1.0")])
        XCTAssertTrue(text.contains("version: 0.1.0"))
        XCTAssertTrue(text.contains("placement\tplaced-caret\tapp=com.apple.TextEdit\tms=8.2") || text.contains("placement\tplaced-caret\tapp=com.apple.TextEdit\tms=8.3"))
        XCTAssertTrue(text.contains("session\toutcome-dispatched"))
    }

    func testFreeTextCannotBeRecorded() {
        let log = DiagnosticsLog()
        log.record(.session, "the user typed hello")
        log.record(.session, "→")
        log.record(.session, "")
        log.record(.session, String(repeating: "a", count: 49))
        XCTAssertTrue(log.snapshot.isEmpty)
    }

    func testApplicationFieldAcceptsOnlyBundleIdentifiers() {
        let log = DiagnosticsLog()
        log.record(.capture, "captured", application: "Secret Document.txt")
        XCTAssertEqual(log.snapshot.count, 1)
        XCTAssertNil(log.snapshot.first?.application)
    }

    func testOldEntriesAreDropped() {
        let log = DiagnosticsLog()
        for _ in 0..<(DiagnosticsLog.capacity + 25) {
            log.record(.session, "tick")
        }
        XCTAssertEqual(log.snapshot.count, DiagnosticsLog.capacity)
    }

    func testClear() {
        let log = DiagnosticsLog()
        log.record(.session, "tick")
        log.clear()
        XCTAssertTrue(log.snapshot.isEmpty)
    }
}
