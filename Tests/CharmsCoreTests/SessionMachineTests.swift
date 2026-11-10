import XCTest
@testable import CharmsCore

final class SessionMachineTests: XCTestCase {
    /// Drives a machine to `browsing` and returns it with its session.
    private func browsing(_ invocation: Invocation = .shortcut, capture: CaptureResult = .insertable) -> (SessionMachine, SessionID) {
        var machine = SessionMachine()
        let effects = machine.handle(.invoke(invocation))
        guard case .capture(let id, _)? = effects.first else {
            XCTFail("expected a capture effect")
            return (machine, SessionID(0))
        }
        _ = machine.handle(.captured(id, capture))
        if invocation == .typedMarker {
            _ = machine.handle(.handoffSettled(id, verified: true))
        }
        return (machine, id)
    }

    func testInvokeStartsCapture() {
        var machine = SessionMachine()
        let effects = machine.handle(.invoke(.shortcut))
        XCTAssertEqual(effects, [.capture(SessionID(1), .shortcut)])
        XCTAssertEqual(machine.state, .capturing)
        XCTAssertFalse(machine.isPickerVisible)
    }

    func testCapturePresentsThePicker() {
        var machine = SessionMachine()
        _ = machine.handle(.invoke(.shortcut))
        XCTAssertEqual(machine.handle(.captured(SessionID(1), .insertable)), [.present(SessionID(1), canInsert: true)])
        XCTAssertEqual(machine.state, .browsing)
        XCTAssertTrue(machine.canInsert)
        XCTAssertTrue(machine.isPickerVisible)
    }

    func testInsertHappyPath() {
        var (machine, id) = browsing()
        XCTAssertEqual(machine.handle(.activate(.insert)), [.awaitRelease(id, .insert)])
        XCTAssertEqual(machine.handle(.keysReleased(id)), [.validate(id)])
        XCTAssertEqual(machine.handle(.validated(id, .valid)), [.dispatch(id)])
        XCTAssertEqual(machine.state, .dispatching)
        XCTAssertEqual(machine.handle(.dispatchFinished(id)), [.finish(id, .dispatched)])
        XCTAssertTrue(machine.isIdle)
    }

    func testCopyHappyPath() {
        var (machine, id) = browsing()
        XCTAssertEqual(machine.handle(.activate(.copy)), [.awaitRelease(id, .copy)])
        XCTAssertEqual(machine.handle(.keysReleased(id)), [.dismiss(id, restoreFocus: true), .copy(id)])
        XCTAssertEqual(machine.handle(.copyFinished(id)), [.finish(id, .copied)])
        XCTAssertTrue(machine.isIdle)
    }

    func testReturnInCopyOnlyModeCopies() {
        var (machine, id) = browsing(.shortcut, capture: .copyOnly)
        XCTAssertFalse(machine.canInsert)
        XCTAssertEqual(machine.handle(.activate(.insert)), [.awaitRelease(id, .copy)])
    }

    func testDoubleReturnDispatchesOnce() {
        var (machine, id) = browsing()
        _ = machine.handle(.activate(.insert))
        XCTAssertEqual(machine.handle(.activate(.insert)), [])
        _ = machine.handle(.keysReleased(id))
        XCTAssertEqual(machine.handle(.activate(.insert)), [])
        XCTAssertEqual(machine.handle(.keysReleased(id)), [], "a second release must not validate again")
        XCTAssertEqual(machine.handle(.validated(id, .valid)), [.dispatch(id)])
        XCTAssertEqual(machine.handle(.validated(id, .valid)), [], "a second validation must not dispatch again")
        XCTAssertEqual(machine.handle(.activate(.insert)), [])
        XCTAssertEqual(machine.handle(.dispatchFinished(id)), [.finish(id, .dispatched)])
        XCTAssertEqual(machine.handle(.dispatchFinished(id)), [])
    }

    func testReturnPlusClickKeepsTheFirstAction() {
        var (machine, id) = browsing()
        XCTAssertEqual(machine.handle(.activate(.copy)), [.awaitRelease(id, .copy)])
        XCTAssertEqual(machine.handle(.activate(.insert)), [])
        XCTAssertEqual(machine.state, .awaitingRelease(.copy))
    }

    func testShortcutWhileVisibleCancels() {
        var (machine, id) = browsing()
        XCTAssertEqual(machine.handle(.invoke(.shortcut)), [.dismiss(id, restoreFocus: true), .finish(id, .cancelled)])
        XCTAssertTrue(machine.isIdle)
    }

    func testMenuBarWhileVisibleCancelsInsteadOfOpeningASecondSession() {
        var (machine, id) = browsing()
        XCTAssertEqual(machine.handle(.invoke(.menuBar)), [.dismiss(id, restoreFocus: true), .finish(id, .cancelled)])
    }

    func testSecondShortcutDuringCaptureCancelsIt() {
        var machine = SessionMachine()
        _ = machine.handle(.invoke(.shortcut))
        XCTAssertEqual(machine.handle(.invoke(.shortcut)), [.finish(SessionID(1), .cancelled)])
        XCTAssertTrue(machine.isIdle)
        // The cancelled capture's late reply is ignored.
        XCTAssertEqual(machine.handle(.captured(SessionID(1), .insertable)), [])
        XCTAssertTrue(machine.isIdle)
    }

    func testHeldShortcutDuringCommitIsIgnored() {
        var (machine, id) = browsing()
        _ = machine.handle(.activate(.insert))
        XCTAssertEqual(machine.handle(.invoke(.shortcut)), [])
        _ = machine.handle(.keysReleased(id))
        XCTAssertEqual(machine.handle(.invoke(.shortcut)), [])
        _ = machine.handle(.validated(id, .valid))
        XCTAssertEqual(machine.handle(.invoke(.shortcut)), [])
        XCTAssertEqual(machine.state, .dispatching)
    }

    func testLateReplyFromAnOlderSessionIsIgnored() {
        var machine = SessionMachine()
        _ = machine.handle(.invoke(.shortcut))
        _ = machine.handle(.cancel)
        _ = machine.handle(.invoke(.shortcut))
        XCTAssertEqual(machine.sessionID, SessionID(2))
        XCTAssertEqual(machine.handle(.captured(SessionID(1), .insertable)), [])
        XCTAssertEqual(machine.state, .capturing)
        XCTAssertEqual(machine.handle(.keysReleased(SessionID(1))), [])
        XCTAssertEqual(machine.handle(.validated(SessionID(1), .valid)), [])
        XCTAssertEqual(machine.handle(.dispatchFinished(SessionID(1))), [])
        XCTAssertEqual(machine.state, .capturing)
    }

    func testCancelWhileBrowsingRestoresFocus() {
        var (machine, id) = browsing()
        XCTAssertEqual(machine.handle(.cancel), [.dismiss(id, restoreFocus: true), .finish(id, .cancelled)])
    }

    func testCancelWhileTheCommitKeyIsHeldWaitsForItsRelease() {
        // Escape pressed with Return still down. Closing at once would hand
        // the keyboard back with Return held, and its repeats would land in
        // the document.
        var (machine, id) = browsing()
        _ = machine.handle(.activate(.insert))
        XCTAssertEqual(machine.handle(.cancel), [])
        XCTAssertEqual(machine.state, .releasingAfterCancel)
        XCTAssertTrue(machine.isPickerVisible)
        XCTAssertTrue(machine.isWaitingForRelease)
        XCTAssertEqual(machine.handle(.keysReleased(id)), [.dismiss(id, restoreFocus: true), .finish(id, .cancelled)])
        XCTAssertTrue(machine.isIdle)
    }

    func testCancelWhileHeldEndsAtTheDeadlineAtTheLatest() {
        var (machine, id) = browsing()
        _ = machine.handle(.activate(.copy))
        _ = machine.handle(.cancel)
        XCTAssertEqual(machine.handle(.releaseDeadlinePassed(id)), [.dismiss(id, restoreFocus: true), .finish(id, .cancelled)])
        XCTAssertTrue(machine.isIdle)
    }

    func testNothingRevivesASessionCancelledWhileHeld() {
        var (machine, id) = browsing()
        _ = machine.handle(.activate(.insert))
        _ = machine.handle(.cancel)
        XCTAssertEqual(machine.handle(.activate(.insert)), [])
        XCTAssertEqual(machine.handle(.invoke(.shortcut)), [])
        XCTAssertEqual(machine.handle(.cancel), [])
        XCTAssertEqual(machine.handle(.validated(id, .valid)), [])
        XCTAssertEqual(machine.state, .releasingAfterCancel)
    }

    func testCancelDuringValidationNeverDispatches() {
        var (machine, id) = browsing()
        _ = machine.handle(.activate(.insert))
        _ = machine.handle(.keysReleased(id))
        XCTAssertEqual(machine.handle(.cancel), [.dismiss(id, restoreFocus: false), .finish(id, .cancelled)])
        XCTAssertEqual(machine.handle(.validated(id, .valid)), [])
        XCTAssertTrue(machine.isIdle)
    }

    func testCancelAfterDispatchStartedIsNotReportedAsCancelled() {
        var (machine, id) = browsing()
        _ = machine.handle(.activate(.insert))
        _ = machine.handle(.keysReleased(id))
        _ = machine.handle(.validated(id, .valid))
        XCTAssertEqual(machine.handle(.cancel), [])
        XCTAssertEqual(machine.state, .dispatching)
        XCTAssertEqual(machine.handle(.dispatchFinished(id)), [.finish(id, .dispatched)])
    }

    func testReleaseDeadlineReturnsToBrowsingWithoutCommit() {
        var (machine, id) = browsing()
        _ = machine.handle(.activate(.insert))
        XCTAssertEqual(machine.handle(.releaseDeadlinePassed(id)), [.activationExpired(id)])
        XCTAssertEqual(machine.state, .browsing)
        // Letting go afterwards does nothing.
        XCTAssertEqual(machine.handle(.keysReleased(id)), [])
        XCTAssertEqual(machine.state, .browsing)
        // A fresh activation works.
        XCTAssertEqual(machine.handle(.activate(.insert)), [.awaitRelease(id, .insert)])
    }

    func testFailedValidationFallsBackToCopyOnly() {
        var (machine, id) = browsing()
        _ = machine.handle(.activate(.insert))
        _ = machine.handle(.keysReleased(id))
        XCTAssertEqual(machine.handle(.validated(id, .copyOnly)), [.present(id, canInsert: false)])
        XCTAssertEqual(machine.state, .browsing)
        XCTAssertFalse(machine.canInsert)
        XCTAssertEqual(machine.handle(.activate(.insert)), [.awaitRelease(id, .copy)])
    }

    func testInvalidContextEndsWithoutDispatch() {
        var (machine, id) = browsing()
        _ = machine.handle(.activate(.insert))
        _ = machine.handle(.keysReleased(id))
        XCTAssertEqual(machine.handle(.validated(id, .invalid)), [.dismiss(id, restoreFocus: false), .finish(id, .failedBeforeDispatch)])
        XCTAssertTrue(machine.isIdle)
    }

    func testTransportThatCannotStartReportsFailedBeforeDispatch() {
        var (machine, id) = browsing()
        _ = machine.handle(.activate(.insert))
        _ = machine.handle(.keysReleased(id))
        _ = machine.handle(.validated(id, .valid))
        XCTAssertEqual(machine.handle(.dispatchNotStarted(id)), [.finish(id, .failedBeforeDispatch)])
    }

    // MARK: Typed invocation

    func testTypedMarkerOpensInHandoff() {
        var machine = SessionMachine()
        _ = machine.handle(.invoke(.typedMarker))
        XCTAssertEqual(machine.handle(.captured(SessionID(1), .insertable)), [.present(SessionID(1), canInsert: true)])
        XCTAssertEqual(machine.state, .handoff)
        XCTAssertEqual(machine.handle(.handoffSettled(SessionID(1), verified: true)), [])
        XCTAssertEqual(machine.state, .browsing)
    }

    func testTypedMarkerWithoutAFieldDoesNotOpen() {
        var machine = SessionMachine()
        _ = machine.handle(.invoke(.typedMarker))
        XCTAssertEqual(machine.handle(.captured(SessionID(1), .copyOnly)), [.finish(SessionID(1), .cancelled)])
        XCTAssertTrue(machine.isIdle)
    }

    func testUnconfirmedMarkerDoesNotOpen() {
        var machine = SessionMachine()
        _ = machine.handle(.invoke(.typedMarker))
        XCTAssertEqual(machine.handle(.markerUnconfirmed(SessionID(1))), [.finish(SessionID(1), .cancelled)])
    }

    func testTypedMarkerNeverInterruptsASession() {
        var (machine, _) = browsing()
        XCTAssertEqual(machine.handle(.invoke(.typedMarker)), [])
        XCTAssertEqual(machine.state, .browsing)
        var capturing = SessionMachine()
        _ = capturing.handle(.invoke(.shortcut))
        XCTAssertEqual(capturing.handle(.invoke(.typedMarker)), [])
        XCTAssertEqual(capturing.state, .capturing)
    }

    func testShortcutSupersedesATypedSession() {
        var machine = SessionMachine()
        _ = machine.handle(.invoke(.typedMarker))
        XCTAssertEqual(machine.handle(.invoke(.shortcut)), [.finish(SessionID(1), .cancelled)])
        XCTAssertEqual(machine.handle(.invoke(.shortcut)), [.capture(SessionID(2), .shortcut)])
        // The typed session's late replies cannot open a second panel.
        XCTAssertEqual(machine.handle(.captured(SessionID(1), .insertable)), [])
        XCTAssertEqual(machine.handle(.handoffSettled(SessionID(1), verified: true)), [])
    }

    func testReturnDuringHandoffWaitsForTheSourceToSettle() {
        var machine = SessionMachine()
        _ = machine.handle(.invoke(.typedMarker))
        let id = SessionID(1)
        _ = machine.handle(.captured(id, .insertable))
        XCTAssertEqual(machine.handle(.activate(.insert)), [])
        XCTAssertEqual(machine.pendingActivation, .insert)
        XCTAssertEqual(machine.handle(.handoffSettled(id, verified: true)), [.awaitRelease(id, .insert)])
        XCTAssertNil(machine.pendingActivation)
    }

    func testPendingInsertIsDroppedWhenTheSourceCannotBeVerified() {
        var machine = SessionMachine()
        _ = machine.handle(.invoke(.typedMarker))
        let id = SessionID(1)
        _ = machine.handle(.captured(id, .insertable))
        _ = machine.handle(.activate(.insert))
        XCTAssertEqual(machine.handle(.handoffSettled(id, verified: false)), [.present(id, canInsert: false)])
        XCTAssertEqual(machine.state, .browsing)
        XCTAssertFalse(machine.canInsert)
        XCTAssertNil(machine.pendingActivation)
    }

    func testPendingCopySurvivesAnUnverifiedHandoff() {
        var machine = SessionMachine()
        _ = machine.handle(.invoke(.typedMarker))
        let id = SessionID(1)
        _ = machine.handle(.captured(id, .insertable))
        _ = machine.handle(.activate(.copy))
        XCTAssertEqual(machine.handle(.handoffSettled(id, verified: false)), [.present(id, canInsert: false), .awaitRelease(id, .copy)])
    }

    func testLateSourceInputReturnsToHandoff() {
        var (machine, id) = browsing(.typedMarker)
        XCTAssertEqual(machine.handle(.sourceReceivedInput(id)), [])
        XCTAssertEqual(machine.state, .handoff)
        XCTAssertEqual(machine.handle(.activate(.insert)), [])
        XCTAssertEqual(machine.handle(.handoffSettled(id, verified: true)), [.awaitRelease(id, .insert)])
    }

    func testSourceInputIsIgnoredForShortcutSessions() {
        var (machine, id) = browsing(.shortcut)
        XCTAssertEqual(machine.handle(.sourceReceivedInput(id)), [])
        XCTAssertEqual(machine.state, .browsing)
    }

    func testEscapeDuringHandoffCancelsWithoutDispatch() {
        var machine = SessionMachine()
        _ = machine.handle(.invoke(.typedMarker))
        let id = SessionID(1)
        _ = machine.handle(.captured(id, .insertable))
        _ = machine.handle(.activate(.insert))
        XCTAssertEqual(machine.handle(.cancel), [.dismiss(id, restoreFocus: true), .finish(id, .cancelled)])
        XCTAssertEqual(machine.handle(.handoffSettled(id, verified: true)), [])
        XCTAssertTrue(machine.isIdle)
    }

    func testSessionIdentifiersAreNeverReused() {
        var machine = SessionMachine()
        var seen = Set<SessionID>()
        for _ in 0..<5 {
            guard case .capture(let id, _)? = machine.handle(.invoke(.shortcut)).first else {
                return XCTFail("expected capture")
            }
            XCTAssertTrue(seen.insert(id).inserted)
            _ = machine.handle(.cancel)
        }
    }
}
