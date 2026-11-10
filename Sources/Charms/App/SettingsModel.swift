import AppKit
import CharmsCore
import Combine
import UniformTypeIdentifiers

/// The state behind the settings window that does not live in the stored
/// preferences: what the system currently allows, and the outcome of the
/// last change that could fail.
@MainActor
final class SettingsModel: ObservableObject {
    let services: AppServices
    private let hotKeys: HotKeyService

    @Published private(set) var canInsert = Permissions.canInsert
    @Published private(set) var launchState = LaunchAtLogin.state
    @Published var shortcutMessage: String?
    @Published var launchMessage: String?
    @Published var dataMessage: String?

    var onCapabilitiesChanged: (() -> Void)?
    var onShowOnboarding: (() -> Void)?
    /// Forgets the answers about applications that hide their text fields,
    /// including those the picker keeps only for this run.
    var onForgetFieldAccessAnswers: (() -> Void)?

    init(services: AppServices, hotKeys: HotKeyService) {
        self.services = services
        self.hotKeys = hotKeys
        if !hotKeys.isAvailable {
            shortcutMessage = "This shortcut could not be registered. Choose another one."
        }
    }

    /// Re-reads what the system reports. Called when the window is shown
    /// and when Charms becomes active again, for example on the way back
    /// from System Settings.
    func refresh() {
        let nowCanInsert = Permissions.canInsert
        if nowCanInsert != canInsert { canInsert = nowCanInsert }
        let nowLaunch = LaunchAtLogin.state
        if nowLaunch != launchState { launchState = nowLaunch }
    }

    // MARK: Shortcut

    func recordingChanged(_ isRecording: Bool) {
        // While the recorder listens, the current shortcut must reach it
        // instead of opening the picker.
        if isRecording {
            hotKeys.suspend()
        } else {
            hotKeys.resume()
        }
    }

    func recorded(_ combo: KeyCombo) {
        let character = KeyLayout.character(forKeyCode: combo.keyCode)
        switch combo.problem(keyCharacter: character) {
        case .needsModifier:
            shortcutMessage = "Add Control, Option or Command, so the shortcut does not get in the way of typing."
            return
        case .reserved:
            shortcutMessage = "\(combo.displayString(keyCharacter: character)) is an editing or system command. Choose another one."
            return
        case nil:
            break
        }
        // The system has the last word: only a combination it accepted is
        // stored. On refusal the previous one keeps working.
        hotKeys.resume()
        guard hotKeys.apply(combo) else {
            shortcutMessage = "\(combo.displayString(keyCharacter: character)) could not be registered. The previous shortcut is still active."
            return
        }
        shortcutMessage = nil
        services.preferences.update { $0.shortcut = combo }
    }

    func resetShortcut() {
        recorded(.standard)
    }

    // MARK: Permissions and login item

    func enableInsertion() {
        Permissions.requestInsertion()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchMessage = LaunchAtLogin.set(enabled)
        launchState = LaunchAtLogin.state
    }

    /// Every application is asked about again when Charms next meets it.
    func forgetFieldAccessAnswers() {
        onForgetFieldAccessAnswers?()
    }

    func setTypedTrigger(_ enabled: Bool) {
        services.preferences.update { $0.typedTriggerEnabled = enabled }
        onCapabilitiesChanged?()
    }

    // MARK: Data

    func clearRecents() {
        services.library.change { $0.clearRecents() }
        dataMessage = "Recents cleared."
    }

    func restoreDefaultFavourites() {
        guard let catalog = services.content?.catalog else { return }
        services.library.change { $0.resetFavourites(to: SeedFavourites.items(in: catalog)) }
        dataMessage = "Favourites restored to the default set."
    }

    func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Charms-diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let preferences = services.preferences.value
        let system = ProcessInfo.processInfo.operatingSystemVersionString
        var header: [(String, String)] = [
            ("version", services.bundleVersion),
            ("system", system),
            ("insertion-enabled", canInsert ? "yes" : "no"),
            ("typed-trigger", preferences.typedTriggerEnabled ? "on" : "off"),
            ("paste-applications", String(preferences.pasteApplications.count)),
            ("pass-through-applications", String(preferences.shortcutPassThrough.count)),
            ("field-access-applications", String(preferences.fieldAccessApplications.count)),
            ("displays", String(NSScreen.screens.count)),
            ("separate-spaces", NSScreen.screensHaveSeparateSpaces ? "yes" : "no")
        ]
        if let catalog = services.content?.catalog {
            header.append(("catalogue", "Unicode \(catalog.header.unicodeVersion), Emoji \(catalog.header.emojiVersion), CLDR \(catalog.header.cldrVersion), \(catalog.entries.count) entries"))
        }
        do {
            try services.diagnostics.export(header: header).write(to: url, atomically: true, encoding: .utf8)
            dataMessage = "Diagnostics saved."
        } catch {
            dataMessage = "Could not save diagnostics: \(error.localizedDescription)"
        }
    }

    // MARK: Application lists

    /// Lets the user pick an application and returns its bundle identifier.
    func chooseApplication() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }

    static func displayName(forBundleIdentifier identifier: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
