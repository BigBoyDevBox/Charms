import AppKit
import Carbon.HIToolbox
import CharmsCore

/// Owns the one global shortcut: registers it, releases it in applications
/// the user wants to keep the keys for themselves, and reports whether the
/// system accepted it.
@MainActor
final class HotKeyService {
    var onPressed: (() -> Void)?

    private let hotKey = CarbonHotKey()
    private let diagnostics: DiagnosticsLog
    private(set) var combo: KeyCombo
    private var passThrough: Set<String> = []
    private var isSuspended = false
    /// False when the system refused the current combination.
    private(set) var isAvailable = false
    private var observer: NSObjectProtocol?

    init(combo: KeyCombo, diagnostics: DiagnosticsLog) {
        self.combo = combo
        self.diagnostics = diagnostics
        hotKey.onPressed = { [weak self] in
            MainActor.assumeIsolated { self?.onPressed?() }
        }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Tries a new combination. On failure the previous one stays in force
    /// and false is returned, so the caller can explain and keep the old
    /// setting.
    @discardableResult
    func apply(_ newCombo: KeyCombo) -> Bool {
        let previous = combo
        combo = newCombo
        if register() {
            return true
        }
        diagnostics.record(.hotKey, "register-failed")
        combo = previous
        _ = register()
        return false
    }

    func setPassThrough(_ applications: Set<String>) {
        passThrough = applications
        refresh()
    }

    /// While the recorder listens for a new combination the current one must
    /// not open the picker.
    func suspend() {
        isSuspended = true
        hotKey.unregister()
    }

    func resume() {
        isSuspended = false
        refresh()
    }

    /// Registers or releases the shortcut for the application now in front.
    func refresh() {
        guard !isSuspended else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let frontmost, BundlePattern.matches(frontmost, in: passThrough) {
            // The application gets its own binding back, for example
            // Control-P as "previous line" in a terminal.
            if hotKey.isRegistered {
                hotKey.unregister()
                diagnostics.record(.hotKey, "released-for-application", application: frontmost)
            }
            return
        }
        if !hotKey.isRegistered {
            _ = register()
        }
    }

    @discardableResult
    private func register() -> Bool {
        isAvailable = hotKey.register(keyCode: UInt32(combo.keyCode), carbonModifiers: Self.carbonModifiers(combo.modifiers))
        return isAvailable
    }

    static func carbonModifiers(_ modifiers: KeyCombo.Modifiers) -> UInt32 {
        var carbon: UInt32 = 0
        if modifiers.contains(.control) { carbon |= UInt32(controlKey) }
        if modifiers.contains(.option) { carbon |= UInt32(optionKey) }
        if modifiers.contains(.shift) { carbon |= UInt32(shiftKey) }
        if modifiers.contains(.command) { carbon |= UInt32(cmdKey) }
        return carbon
    }

    static func modifiers(from flags: NSEvent.ModifierFlags) -> KeyCombo.Modifiers {
        var modifiers: KeyCombo.Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }

    /// The shortcut as it should be printed for the active layout.
    static func displayString(for combo: KeyCombo) -> String {
        combo.displayString(keyCharacter: KeyLayout.character(forKeyCode: combo.keyCode))
    }
}
