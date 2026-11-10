import Foundation

/// Where Charms keeps its files.
///
/// Setting `CHARMS_HOME` moves everything, preferences included, into that
/// directory. The end-to-end checks use it so that they never read or change
/// the real user's favourites and settings.
struct AppPaths {
    let supportDirectory: URL
    /// True when `CHARMS_HOME` redirected storage.
    let isIsolated: Bool

    static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> AppPaths {
        if let home = environment["CHARMS_HOME"], !home.isEmpty {
            return AppPaths(supportDirectory: URL(fileURLWithPath: home, isDirectory: true), isIsolated: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return AppPaths(supportDirectory: base.appendingPathComponent("Charms", isDirectory: true), isIsolated: false)
    }

    var lockFile: URL { supportDirectory.appendingPathComponent("charms.lock") }
    var preferencesFile: URL { supportDirectory.appendingPathComponent("preferences.json") }
}

/// Makes sure only one Charms owns the shortcut and the menu-bar item.
///
/// A file lock is atomic, which looking through the list of running
/// applications is not: two copies started together would both find nobody
/// else. The lock is released by the system when the process ends, however
/// it ends.
final class SingleInstance {
    private var descriptor: Int32 = -1

    /// Returns false when another instance already holds the lock.
    func acquire(at url: URL) -> Bool {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        descriptor = open(url.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else {
            // Without a lock file the app still has to be usable.
            return true
        }
        if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            close(descriptor)
            descriptor = -1
            return false
        }
        return true
    }

    static let showSettingsNotification = Notification.Name("ch.lkmc.Charms.showSettings")
}
