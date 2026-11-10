import AppKit
import ApplicationServices

/// The one privacy permission Charms uses, and how to ask for it.
///
/// Accessibility access lets Charms find the field being typed in, send the
/// chosen character to that application, and, when the typed trigger is on,
/// notice the two colons. Without it Charms still browses and copies.
enum Permissions {
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Insertion needs both the Accessibility trust and the right to post
    /// keyboard events. The system grants them together, but they are
    /// separate questions and each is asked.
    static var canInsert: Bool {
        AXIsProcessTrusted() && CGPreflightPostEventAccess()
    }

    @MainActor private static var hasShownSystemPrompt = false

    /// Asks for the permission. Only ever called from a button the user
    /// pressed.
    ///
    /// The first call in a launch shows the system's own prompt, which also
    /// adds Charms to the list in System Settings and offers to open it.
    /// The system shows that prompt once, so later calls open the list
    /// directly. Doing both at once left the prompt open behind System
    /// Settings after the switch had been turned on (seen on macOS 27).
    @MainActor
    static func requestInsertion() {
        guard !hasShownSystemPrompt else {
            openAccessibilitySettings()
            return
        }
        hasShownSystemPrompt = true
        // The key is spelled out because the SDK exposes it as a mutable C
        // global, which strict concurrency checking refuses to read.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// The list is called Accessibility up to macOS 26 and Device Control
    /// and Data Access on macOS 27; the same address opens both.
    private static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
