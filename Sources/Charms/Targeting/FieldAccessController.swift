import AppKit
import CharmsCore

/// Offers to switch on text field reporting in an application that hides
/// its fields, remembers the answer, and keeps the applications the user
/// agreed about switched on (see `FieldAccess`).
@MainActor
final class FieldAccessController {
    private let services: AppServices
    private let capture: TargetCaptureService
    /// Applications already asked about during this run. "Not Now" lasts
    /// until Charms is started again.
    private var asked: Set<String> = []
    private var observer: NSObjectProtocol?

    enum Result: Equatable {
        /// The application is in front and reports its fields.
        case reportsFields
        /// The application is in front; Charms can still only copy there.
        case stillHidden
        /// The user went on to another application meanwhile.
        case userMovedOn
    }

    /// True while the question is on screen. Charms is the active
    /// application then, and no picker session may start.
    private(set) var isAsking = false

    init(services: AppServices, capture: TargetCaptureService) {
        self.services = services
        self.capture = capture

        // An application the user agreed about has its tree off again after
        // every start. Asking when it comes to the front means the field is
        // there by the time the picker is wanted.
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.keepOn(application) }
        }
        keepOn(NSWorkspace.shared.frontmostApplication)
    }

    func step(for target: CapturedTarget) -> FieldAccess.Step {
        let preferences = services.preferences.value
        return FieldAccess.step(
            bundleIdentifier: target.bundleIdentifier, hidesFields: target.hidesFields,
            allowed: preferences.fieldAccessApplications, declined: preferences.fieldAccessDeclined, asked: asked
        )
    }

    /// Switches reporting on for an application the user agreed about.
    func request(_ target: CapturedTarget) {
        capture.requestFieldsIfHidden(processID: target.processID)
    }

    /// Asks the user about the application, records the answer and carries
    /// it out. `completion` runs once the application has the keyboard back
    /// and, if the user agreed, has had time to report its fields.
    ///
    /// - Parameter returnTurnsOn: whether Return answers "Turn On". Not
    ///   while the user is typing: keys typed after `::` land in the
    ///   question and must not answer it.
    func offer(for target: CapturedTarget, returnTurnsOn: Bool, completion: @escaping @MainActor (Result) -> Void) {
        guard let identifier = target.bundleIdentifier, !isAsking else {
            completion(.userMovedOn)
            return
        }
        asked.insert(identifier)
        isAsking = true
        services.diagnostics.record(.capture, "field-access-offered", application: identifier)

        let name = target.applicationName ?? identifier
        let alert = NSAlert()
        alert.messageText = "Let Charms insert into \(name)?"
        alert.informativeText = "\(name) does not report where you are typing unless an app requests it, so Charms can only copy characters there.\n\nIf you turn this on, Charms requests it now and each time \(name) starts. It takes about two seconds to take effect, and \(name) may use a little more memory and processor time."
        let turnOn = alert.addButton(withTitle: "Turn On")
        let notNow = alert.addButton(withTitle: "Not Now")
        if !returnTurnsOn {
            turnOn.keyEquivalent = ""
        }
        notNow.keyEquivalent = "\u{1b}"
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Do not ask again for \(name)"

        // An accessory app has to come to the front to show a question.
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        isAsking = false

        let answer: FieldAccess.Answer = response == .alertFirstButtonReturn
            ? .turnOn
            : .decline(remember: alert.suppressionButton?.state == .on)
        services.preferences.update { FieldAccess.record(answer, for: identifier, in: &$0) }

        // Typing continues where it was.
        let source = NSRunningApplication(processIdentifier: target.processID)
        source?.activate()

        guard answer == .turnOn else {
            services.diagnostics.record(.capture, "field-access-declined", application: identifier)
            Self.whenFrontmost(target.processID) { isFrontmost in
                completion(isFrontmost ? .stillHidden : .userMovedOn)
            }
            return
        }
        capture.requestFields(processID: target.processID) { [services] appeared in
            services.diagnostics.record(.capture, appeared ? "field-access-on" : "field-access-no-answer", application: identifier)
            Self.whenFrontmost(target.processID) { isFrontmost in
                completion(!isFrontmost ? .userMovedOn : appeared ? .reportsFields : .stillHidden)
            }
        }
    }

    private func keepOn(_ application: NSRunningApplication?) {
        guard let application, let identifier = application.bundleIdentifier,
              services.preferences.value.fieldAccessApplications.contains(identifier) else {
            return
        }
        capture.requestFieldsIfHidden(processID: application.processIdentifier)
    }

    /// Runs `action` with true once the application is frontmost, or with
    /// false after a second if it does not get there: the user may have
    /// gone elsewhere.
    private static func whenFrontmost(_ processID: pid_t, attempt: Int = 0, _ action: @escaping @MainActor (Bool) -> Void) {
        let isFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == processID
        if isFrontmost || attempt >= 20 {
            action(isFrontmost)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            MainActor.assumeIsolated { whenFrontmost(processID, attempt: attempt + 1, action) }
        }
    }
}
