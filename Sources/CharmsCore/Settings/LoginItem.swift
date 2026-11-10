import Foundation

/// What the "Open Charms at login" switch may show, decided from what the
/// system reports and from where the app is running.
public enum LoginItem {
    /// The system's answer about the app's login item.
    public enum Status: Equatable, Sendable, CaseIterable {
        case enabled
        /// Registered, but switched off or not yet allowed in System Settings.
        case requiresApproval
        case notRegistered
        /// The system has no record of the login item. This is the answer
        /// for every app that has never registered one, wherever it is
        /// installed, so it says nothing about the installation. Measured on
        /// macOS 27.0.1 with an ad-hoc signed app in the Applications
        /// folder: "not found" at first, registering succeeds from there,
        /// and after unregistering the answer is "not registered".
        case notFound
    }

    public enum State: Equatable, Sendable {
        case off
        case on
        /// Registered, but the user has to allow it in System Settings.
        case needsApproval
        /// The app runs from a place a login item must not point to.
        case unavailable
    }

    /// An item the system knows is shown as the system reports it, so it can
    /// always be switched off. Otherwise the switch is usable and the system
    /// has the last word when it is switched on. The one exception is an app
    /// running translocated: its path is gone at the next launch.
    public static func state(for status: Status, bundlePath: String) -> State {
        switch status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        case .notRegistered, .notFound: return isTranslocated(bundlePath) ? .unavailable : .off
        }
    }

    /// macOS runs a downloaded app that was opened where it landed, in
    /// Downloads or on its disk image, from a read-only copy at a random
    /// path that changes with every launch. It stops doing so once the app
    /// has been moved with the Finder.
    public static func isTranslocated(_ bundlePath: String) -> Bool {
        bundlePath.contains("/AppTranslocation/")
    }
}
