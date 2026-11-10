import AppKit
import Carbon.HIToolbox
import CharmsCore

/// Watches for `::` typed into another application, while the user has
/// switched that on.
///
/// The observer is an `NSEvent` global monitor. It reports exactly the keys
/// that were delivered to other applications, which is what the handoff
/// needs to know: a key that shows up here went to the source, a key that
/// does not went to the picker. Nothing is kept beyond the recogniser's one
/// candidate colon; no key is logged or stored.
@MainActor
final class TypedTriggerService {
    /// Asked before each key: whether a session is running, and of which kind.
    var sessionState: (() -> SessionActivity)?
    /// A marker was completed in this process.
    var onTriggered: ((pid_t) -> Void)?
    /// During a typed session: a key reached the source application.
    var onSourceKey: ((KeyObservation) -> Void)?

    enum SessionActivity {
        case none
        /// A typed session whose source is this process.
        case typed(pid_t)
        case other
    }

    private let diagnostics: DiagnosticsLog
    private var recognizer = TriggerRecognizer()
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var isEnabled = false
    private var exclusions: Set<String> = []

    init(diagnostics: DiagnosticsLog) {
        self.diagnostics = diagnostics
    }

    var isObserving: Bool { keyMonitor != nil }

    /// Installs or removes the observer to match the settings and the
    /// permission state. Called at launch, when settings change, and when
    /// the permission may have changed.
    func update(enabled: Bool, exclusions: Set<String>) {
        isEnabled = enabled
        self.exclusions = exclusions
        let eligibility = TriggerEligibility(
            isEnabled: enabled, hasAccessibility: Permissions.canInsert,
            isSecureInputActive: false, isSessionActive: false, isInputMethodActive: false
        )
        if eligibility.observerBlocker == nil {
            install()
        } else {
            remove()
        }
    }

    private func install() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        // A click moves the caret or the focus; what was typed before it no
        // longer says anything about what precedes the next colon.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.recognizer.reset() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.recognizer.reset() }
            })
        }
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recognizer.reset() }
        })
        diagnostics.record(.trigger, "observer-installed")
    }

    private func remove() {
        guard keyMonitor != nil else { return }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        keyMonitor = nil
        mouseMonitor = nil
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observers.removeAll()
        recognizer.reset()
        diagnostics.record(.trigger, "observer-removed")
    }

    /// Forgets a half-typed marker, for example when the shortcut is used.
    func reset() {
        recognizer.reset()
    }

    private func handle(_ event: NSEvent) {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let processID = frontmost?.processIdentifier ?? 0
        let flags = event.modifierFlags
        let key = KeyObservation(
            characters: event.characters ?? "",
            isRepeat: event.isARepeat,
            isShortcut: flags.contains(.command) || flags.contains(.control),
            processID: processID,
            timestamp: event.timestamp
        )

        switch sessionState?() ?? .none {
        case .typed(let source):
            // Recognition is suspended for the whole session, so query text
            // can never start a second one.
            recognizer.reset()
            if source == processID { onSourceKey?(key) }
            return
        case .other:
            recognizer.reset()
            return
        case .none:
            break
        }

        let eligibility = TriggerEligibility(
            isEnabled: isEnabled, hasAccessibility: Permissions.canInsert,
            isSecureInputActive: IsSecureEventInputEnabled(), isSessionActive: false,
            isInputMethodActive: KeyLayout.isInputMethodActive
        )
        if eligibility.blocker(forBundleIdentifier: frontmost?.bundleIdentifier, ownBundleIdentifier: Bundle.main.bundleIdentifier, exclusions: exclusions) != nil {
            recognizer.reset()
            return
        }
        guard case .triggered(let source) = recognizer.observe(key) else { return }
        // Colons typed straight after visible text, as in `std::`, are not a
        // marker. Anything else is decided by reading the source.
        if recognizer.lastBoundary == .text {
            diagnostics.record(.trigger, "ignored-after-text")
            return
        }
        onTriggered?(source)
    }
}
