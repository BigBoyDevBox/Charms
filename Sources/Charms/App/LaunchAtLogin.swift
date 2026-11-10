import CharmsCore
import Foundation
import ServiceManagement

/// Launch at login through the system's login-item service. The state is
/// always read back from the system, never remembered separately, so the
/// setting shows what is actually registered.
enum LaunchAtLogin {
    static var state: LoginItem.State {
        LoginItem.state(for: systemStatus, bundlePath: Bundle.main.bundlePath)
    }

    private static var systemStatus: LoginItem.Status {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .notRegistered
        case .notFound: return .notFound
        // An answer this build does not know: leave the switch usable and
        // let registering report what is wrong.
        @unknown default: return .notFound
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
