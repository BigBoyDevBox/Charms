import Foundation
import ServiceManagement

/// Launch at login through the system's login-item service. The state is
/// always read back from the system, never remembered separately, so the
/// setting shows what is actually registered.
enum LaunchAtLogin {
    enum State: Equatable {
        case off
        case on
        /// Registered, but the user has to allow it in System Settings.
        case needsApproval
        /// The app is not running from an installed bundle.
        case unavailable
    }

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        case .notRegistered: return .off
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }

    /// Returns an explanation when the change did not take.
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
