import Foundation

/// Everything the user can configure. Stored as one small document so a
/// missing or newer field never costs the user their other choices.
public struct Preferences: Codable, Equatable, Sendable {
    public var shortcut: KeyCombo
    public var skinTone: SkinTone
    /// Open the picker by typing `::`. Off until the user turns it on. The
    /// same switch is the pause control in the menu, and being stored it
    /// survives relaunch: observation is never resumed silently.
    public var typedTriggerEnabled: Bool
    /// Applications where `::` stays ordinary text.
    public var triggerExclusions: Set<String>
    /// Applications that get the paste backend instead of keyboard events.
    public var pasteApplications: Set<String>
    /// Applications that keep the shortcut for themselves.
    public var shortcutPassThrough: Set<String>
    /// Applications the user agreed Charms may ask to report their text
    /// fields (see `FieldAccess`). Charms asks them each time they start.
    public var fieldAccessApplications: Set<String>
    /// Applications for which the user does not want to be asked.
    public var fieldAccessDeclined: Set<String>
    public var hasCompletedOnboarding: Bool

    public init(
        shortcut: KeyCombo = .standard,
        skinTone: SkinTone = .none,
        typedTriggerEnabled: Bool = false,
        triggerExclusions: Set<String> = DefaultApplications.triggerExclusions,
        pasteApplications: Set<String> = [],
        shortcutPassThrough: Set<String> = [],
        fieldAccessApplications: Set<String> = [],
        fieldAccessDeclined: Set<String> = [],
        hasCompletedOnboarding: Bool = false
    ) {
        self.shortcut = shortcut
        self.skinTone = skinTone
        self.typedTriggerEnabled = typedTriggerEnabled
        self.triggerExclusions = triggerExclusions
        self.pasteApplications = pasteApplications
        self.shortcutPassThrough = shortcutPassThrough
        self.fieldAccessApplications = fieldAccessApplications
        self.fieldAccessDeclined = fieldAccessDeclined
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    private enum CodingKeys: String, CodingKey {
        case shortcut, skinTone, typedTriggerEnabled
        case triggerExclusions, pasteApplications, shortcutPassThrough, hasCompletedOnboarding
        case fieldAccessApplications, fieldAccessDeclined
    }

    /// Decodes leniently: a field that is absent or unreadable takes its
    /// default instead of failing the whole document.
    public init(from decoder: Decoder) throws {
        let defaults = Preferences()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        shortcut = value(.shortcut, defaults.shortcut)
        skinTone = value(.skinTone, defaults.skinTone)
        typedTriggerEnabled = value(.typedTriggerEnabled, defaults.typedTriggerEnabled)
        triggerExclusions = value(.triggerExclusions, defaults.triggerExclusions)
        pasteApplications = value(.pasteApplications, defaults.pasteApplications)
        shortcutPassThrough = value(.shortcutPassThrough, defaults.shortcutPassThrough)
        fieldAccessApplications = value(.fieldAccessApplications, defaults.fieldAccessApplications)
        fieldAccessDeclined = value(.fieldAccessDeclined, defaults.fieldAccessDeclined)
        hasCompletedOnboarding = value(.hasCompletedOnboarding, defaults.hasCompletedOnboarding)
    }

    public static let storageKey = "preferences.v1"

    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Encoding this value type cannot fail.
        return (try? encoder.encode(self)) ?? Data()
    }

    /// Reads stored preferences; anything unreadable yields the defaults.
    public static func decoded(from data: Data?) -> Preferences {
        guard let data, let preferences = try? JSONDecoder().decode(Preferences.self, from: data) else {
            return Preferences()
        }
        return preferences
    }
}

/// Bundle identifiers used as starting points for the per-application lists.
/// They are data the user can edit, not rules built into the logic.
public enum DefaultApplications {
    /// Where `::` is common in ordinary text, or where an emoji shortcode
    /// feature already answers a colon, or where observing typing would be
    /// out of place.
    public static let triggerExclusions: Set<String> = [
        // Terminals
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "net.kovidgoyal.kitty",
        "com.mitchellh.ghostty", "org.alacritty", "co.zeit.hyper", "com.github.wez.wezterm",
        // Code editors
        "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.visualstudio.code.oss",
        "com.todesktop.230313mzl4w4u92", "dev.zed.Zed", "com.sublimetext.4", "com.sublimetext.3",
        "com.jetbrains.*", "com.google.android.studio", "org.vim.MacVim", "org.gnu.Emacs",
        "com.panic.Nova", "com.barebones.bbedit", "com.macromates.TextMate",
        // Applications with their own colon shortcodes
        "com.tinyspeck.slackmacgap", "com.hnc.Discord", "com.microsoft.teams2", "notion.id",
        "md.obsidian", "ru.keepcoder.Telegram", "net.whatsapp.WhatsApp", "org.whispersystems.signal-desktop",
        "com.linear", "com.github.GitHubClient",
        // Password managers
        "com.apple.Passwords", "com.apple.keychainaccess", "com.1password.1password", "com.agilebits.onepassword7",
        "com.bitwarden.desktop", "org.keepassxc.keepassxc", "com.lastpass.LastPass", "com.dashlane.dashlanephonefinal",
        // Remote and virtualised input
        "com.apple.ScreenSharing", "com.microsoft.rdc.macos", "com.vmware.fusion", "com.parallels.desktop.console",
        "com.utmapp.UTM", "com.realvnc.vncviewer", "com.teamviewer.TeamViewer", "com.citrix.receiver.icaviewer.mac"
    ]

    /// Offered in settings as likely candidates for keeping Control-P, which
    /// means "previous line" or "previous command" there.
    public static let passThroughSuggestions: [String] = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "org.gnu.Emacs", "org.vim.MacVim"
    ]
}
