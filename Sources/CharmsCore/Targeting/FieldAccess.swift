import Foundation

/// What to do about an application that hides its text fields.
///
/// Applications built on Chromium, Electron ones among them, keep their
/// accessibility tree switched off until a client asks for it. Until then
/// they report no focused element, and Charms has no field to insert into:
/// it can only copy. Such an application says so itself: it answers the
/// `AXManualAccessibility` attribute with "off". Setting that attribute
/// switches the tree on until the application quits. Measured with Electron
/// 45 on macOS 27: the focused field is reported about two seconds later.
///
/// Switching it on changes how another application runs, so it is the
/// user's decision, made once per application and remembered.
public enum FieldAccess {
    public enum Step: Equatable, Sendable {
        /// Nothing to do, or nothing the user wants done.
        case leave
        /// The user agreed for this application earlier: switch it on.
        case request
        /// Ask the user.
        case offer
    }

    public enum Answer: Equatable, Sendable {
        case turnOn
        /// Not now. `remember` is the "do not ask again" box.
        case decline(remember: Bool)
    }

    /// - Parameters:
    ///   - hidesFields: the application reported no focused element and
    ///     answered that its accessibility tree is off.
    ///   - asked: applications already asked about during this run.
    public static func step(
        bundleIdentifier: String?, hidesFields: Bool,
        allowed: Set<String>, declined: Set<String>, asked: Set<String>
    ) -> Step {
        // Without an identifier there is nothing to remember the answer by.
        guard hidesFields, let bundleIdentifier, !bundleIdentifier.isEmpty else { return .leave }
        if allowed.contains(bundleIdentifier) { return .request }
        if declined.contains(bundleIdentifier) || asked.contains(bundleIdentifier) { return .leave }
        return .offer
    }

    /// Records an answer. An application is never in both lists.
    public static func record(_ answer: Answer, for bundleIdentifier: String, in preferences: inout Preferences) {
        switch answer {
        case .turnOn:
            preferences.fieldAccessApplications.insert(bundleIdentifier)
            preferences.fieldAccessDeclined.remove(bundleIdentifier)
        case .decline(let remember):
            preferences.fieldAccessApplications.remove(bundleIdentifier)
            if remember {
                preferences.fieldAccessDeclined.insert(bundleIdentifier)
            }
        }
    }

    /// Forgets every answer, so each application is asked about again.
    public static func forgetAnswers(in preferences: inout Preferences) {
        preferences.fieldAccessApplications = []
        preferences.fieldAccessDeclined = []
    }
}
