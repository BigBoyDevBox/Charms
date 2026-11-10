import Foundation

/// Identifies one invocation of the picker. Every asynchronous reply carries
/// the identifier it was started for, so a late answer can never act on a
/// newer session.
public struct SessionID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UInt64
    public init(_ rawValue: UInt64) { self.rawValue = rawValue }
    public var description: String { "session-\(rawValue)" }
}

public enum Invocation: String, Equatable, Sendable {
    case shortcut
    case menuBar
    case typedMarker
}

public enum SessionAction: String, Equatable, Sendable {
    case insert
    case copy
}

/// How a session ended. A posted keyboard event has no delivery receipt, so
/// `dispatched` means "sent once", never "verified in the document".
public enum SessionOutcome: String, Equatable, Sendable {
    case cancelled
    case copied
    case dispatched
    case failedBeforeDispatch
}

public enum SessionState: Equatable, Sendable {
    case idle
    /// Reading the source application's focus and geometry.
    case capturing
    /// Typed invocation: the picker is visible and accepts the query while
    /// the text that reached the source is still being reconciled. A commit
    /// made now is held until that settles.
    case handoff
    case browsing
    /// A choice was made; waiting for the keys or button that made it to be
    /// released.
    case awaitingRelease(SessionAction)
    /// Cancelled while the key or button that made a choice was still down.
    /// The picker stays, and keeps the keyboard, until it is released:
    /// closing at once would hand the keyboard back with Return held, and
    /// its repeats would land in the source.
    case releasingAfterCancel
    /// Focus is being handed back and the target checked one last time.
    case validating
    case copying
    /// The one dispatch is in progress. From here on the session can only end
    /// as `dispatched`, or as `failedBeforeDispatch` when nothing was sent.
    case dispatching
}

/// What capture found.
public enum CaptureResult: Equatable, Sendable {
    /// A focused, non-secure field in another application.
    case insertable
    /// No trustworthy field: browse and copy only.
    case copyOnly
}

public enum ValidationResult: Equatable, Sendable {
    case valid
    /// The target is gone or changed but the picker can still offer Copy.
    case copyOnly
    /// The context is gone altogether.
    case invalid
}

public enum SessionEvent: Equatable, Sendable {
    case invoke(Invocation)
    case captured(SessionID, CaptureResult)
    /// Typed invocation only: the marker could not be confirmed in the source.
    case markerUnconfirmed(SessionID)
    /// Typed invocation: more of the query reached the source after all.
    case sourceReceivedInput(SessionID)
    /// Typed invocation: the source text matches what was typed (or not).
    case handoffSettled(SessionID, verified: Bool)
    /// Return or a click on a cell (`insert`), or Command-Return (`copy`).
    case activate(SessionAction)
    case keysReleased(SessionID)
    case releaseDeadlinePassed(SessionID)
    case validated(SessionID, ValidationResult)
    /// The transport sent its input. This is past the commit boundary.
    case dispatchFinished(SessionID)
    /// The transport could not even start; nothing was sent.
    case dispatchNotStarted(SessionID)
    case copyFinished(SessionID)
    /// Escape, an outside click, the panel losing key status, a display or
    /// Space change, sleep, or the source application going away.
    case cancel
}

public enum SessionEffect: Equatable, Sendable {
    case capture(SessionID, Invocation)
    /// Show the picker, or update it after a change of mode.
    case present(SessionID, canInsert: Bool)
    /// Remove the picker. `restoreFocus` asks for the source to get keyboard
    /// focus back if it is still the current context.
    case dismiss(SessionID, restoreFocus: Bool)
    case awaitRelease(SessionID, SessionAction)
    case validate(SessionID)
    case dispatch(SessionID)
    case copy(SessionID)
    /// The pending choice was dropped because keys stayed held too long.
    case activationExpired(SessionID)
    case finish(SessionID, SessionOutcome)
}

/// The single authority on what the picker may do next.
///
/// It is a pure state table: events go in, the effects to carry out come
/// back. The application layer owns all side effects and reports their
/// completion as further events. That keeps the rules that matter most
/// testable without another application: one session at a time, at most one
/// dispatch per session, no dispatch after cancellation, and no late reply
/// acting on a session it does not belong to.
public struct SessionMachine: Sendable {
    public private(set) var state: SessionState = .idle
    public private(set) var sessionID: SessionID?
    public private(set) var invocation: Invocation?
    /// True while the session has a validated field to insert into.
    public private(set) var canInsert = false
    /// A choice made during `handoff`, waiting for the source text to settle.
    public private(set) var pendingActivation: SessionAction?

    private var nextID: UInt64 = 1

    public init() {}

    public var isIdle: Bool { state == .idle }

    /// True while the picker is on screen and accepting input.
    public var isPickerVisible: Bool {
        switch state {
        case .handoff, .browsing, .awaitingRelease, .releasingAfterCancel: return true
        case .idle, .capturing, .validating, .copying, .dispatching: return false
        }
    }

    /// True while the controller should keep watching for the keys and the
    /// mouse button to come up.
    public var isWaitingForRelease: Bool {
        switch state {
        case .awaitingRelease, .releasingAfterCancel: return true
        case .idle, .capturing, .handoff, .browsing, .validating, .copying, .dispatching: return false
        }
    }

    public mutating func handle(_ event: SessionEvent) -> [SessionEffect] {
        switch event {
        case .invoke(let invocation):
            return invoke(invocation)
        case .cancel:
            return cancel()
        case .activate(let action):
            return activate(action)
        case .captured(let id, let result):
            guard isCurrent(id), state == .capturing else { return [] }
            canInsert = result == .insertable
            if invocation == .typedMarker {
                // A typed marker without a field to replace it in has nothing
                // to offer; opening would only interrupt typing.
                guard canInsert else { return end(.cancelled, dismiss: false) }
                state = .handoff
            } else {
                state = .browsing
            }
            return [.present(id, canInsert: canInsert)]
        case .markerUnconfirmed(let id):
            guard isCurrent(id), state == .capturing || state == .handoff else { return [] }
            if state == .capturing {
                return end(.cancelled, dismiss: false)
            }
            return settleHandoff(id, verified: false)
        case .sourceReceivedInput(let id):
            guard isCurrent(id), invocation == .typedMarker, state == .browsing, canInsert else { return [] }
            state = .handoff
            return []
        case .handoffSettled(let id, let verified):
            guard isCurrent(id), state == .handoff else { return [] }
            return settleHandoff(id, verified: verified)
        case .keysReleased(let id):
            guard isCurrent(id) else { return [] }
            if state == .releasingAfterCancel {
                return end(.cancelled, dismiss: true, restoreFocus: true)
            }
            guard case .awaitingRelease(let action) = state else { return [] }
            switch action {
            case .insert:
                state = .validating
                return [.validate(id)]
            case .copy:
                state = .copying
                return [.dismiss(id, restoreFocus: true), .copy(id)]
            }
        case .releaseDeadlinePassed(let id):
            guard isCurrent(id) else { return [] }
            if state == .releasingAfterCancel {
                // Held for a whole second after cancelling: close anyway.
                return end(.cancelled, dismiss: true, restoreFocus: true)
            }
            guard case .awaitingRelease = state else { return [] }
            // Releasing the keys later must not insert by itself: the choice
            // is dropped and a fresh activation is required.
            state = .browsing
            return [.activationExpired(id)]
        case .validated(let id, let result):
            guard isCurrent(id), state == .validating else { return [] }
            switch result {
            case .valid:
                state = .dispatching
                return [.dispatch(id)]
            case .copyOnly:
                canInsert = false
                state = .browsing
                return [.present(id, canInsert: false)]
            case .invalid:
                return end(.failedBeforeDispatch, dismiss: true, restoreFocus: false)
            }
        case .dispatchFinished(let id):
            guard isCurrent(id), state == .dispatching else { return [] }
            return end(.dispatched, dismiss: false)
        case .dispatchNotStarted(let id):
            guard isCurrent(id), state == .dispatching else { return [] }
            return end(.failedBeforeDispatch, dismiss: false)
        case .copyFinished(let id):
            guard isCurrent(id), state == .copying else { return [] }
            return end(.copied, dismiss: false)
        }
    }

    private func isCurrent(_ id: SessionID) -> Bool {
        sessionID == id
    }

    private mutating func invoke(_ newInvocation: Invocation) -> [SessionEffect] {
        switch state {
        case .idle:
            let id = SessionID(nextID)
            nextID += 1
            sessionID = id
            invocation = newInvocation
            canInsert = false
            pendingActivation = nil
            state = .capturing
            return [.capture(id, newInvocation)]
        case .capturing, .handoff, .browsing:
            // The shortcut and the menu item toggle. A typed marker never
            // interrupts a session: recognition is suspended while one runs.
            guard newInvocation != .typedMarker else { return [] }
            return cancel()
        case .awaitingRelease, .releasingAfterCancel, .validating, .copying, .dispatching:
            // A commit is under way; a held or repeated shortcut must not
            // turn it into a cancellation or a second session.
            return []
        }
    }

    private mutating func activate(_ action: SessionAction) -> [SessionEffect] {
        guard let id = sessionID else { return [] }
        switch state {
        case .browsing:
            let effective: SessionAction = (action == .insert && !canInsert) ? .copy : action
            state = .awaitingRelease(effective)
            return [.awaitRelease(id, effective)]
        case .handoff:
            // Only the first choice counts; it is resolved once the source
            // text is proved.
            if pendingActivation == nil {
                pendingActivation = action
            }
            return []
        case .idle, .capturing, .awaitingRelease, .releasingAfterCancel, .validating, .copying, .dispatching:
            // A second Return, or a click arriving with a Return, is ignored.
            return []
        }
    }

    private mutating func settleHandoff(_ id: SessionID, verified: Bool) -> [SessionEffect] {
        state = .browsing
        var effects: [SessionEffect] = []
        if !verified {
            canInsert = false
            effects.append(.present(id, canInsert: false))
        }
        guard let pending = pendingActivation else { return effects }
        pendingActivation = nil
        if pending == .insert, !verified {
            // The choice was made for an insertion that can no longer be
            // offered. Copying instead would not be what was asked for.
            return effects
        }
        state = .awaitingRelease(pending)
        effects.append(.awaitRelease(id, pending))
        return effects
    }

    private mutating func cancel() -> [SessionEffect] {
        switch state {
        case .idle, .copying, .dispatching:
            // Nothing to cancel, or the commit boundary has been passed.
            return []
        case .capturing:
            return end(.cancelled, dismiss: false)
        case .handoff, .browsing:
            return end(.cancelled, dismiss: true, restoreFocus: true)
        case .awaitingRelease:
            // The choice is dropped now; the picker closes when the key or
            // button that made it comes up.
            state = .releasingAfterCancel
            return []
        case .releasingAfterCancel:
            return []
        case .validating:
            // The picker is already hidden and focus is on its way back.
            return end(.cancelled, dismiss: true, restoreFocus: false)
        }
    }

    private mutating func end(_ outcome: SessionOutcome, dismiss: Bool, restoreFocus: Bool = false) -> [SessionEffect] {
        guard let id = sessionID else { return [] }
        state = .idle
        sessionID = nil
        invocation = nil
        canInsert = false
        pendingActivation = nil
        var effects: [SessionEffect] = []
        if dismiss {
            effects.append(.dismiss(id, restoreFocus: restoreFocus))
        }
        effects.append(.finish(id, outcome))
        return effects
    }
}
