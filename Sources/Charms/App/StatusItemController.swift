import AppKit
import CharmsCore
import Combine

/// The menu-bar item: the way in without a keyboard, and the one place that
/// is always visible to turn the typed trigger on and off.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let services: AppServices
    private let openItem = NSMenuItem(title: "Open Charms", action: #selector(openPicker), keyEquivalent: "")
    private let triggerItem = NSMenuItem(title: "Open by Typing ::", action: #selector(toggleTrigger), keyEquivalent: "")

    var onOpenPicker: (() -> Void)?
    var onShowSettings: (() -> Void)?
    var onShowAbout: (() -> Void)?

    init(services: AppServices) {
        self.services = services
        super.init()
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Charms")
            image?.isTemplate = true
            button.image = image
            if image == nil { button.title = "✦" }
            button.toolTip = "Charms"
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        openItem.target = self
        triggerItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())
        menu.addItem(triggerItem)
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings), key: ","))
        menu.addItem(item("About Charms", #selector(showAbout)))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Charms", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    /// The menu shows the current state every time it opens, so it cannot
    /// drift from the settings or from a permission changed elsewhere.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let preferences = services.preferences.value
        openItem.title = "Open Charms    \(HotKeyService.displayString(for: preferences.shortcut))"
        let canInsert = Permissions.canInsert
        triggerItem.state = preferences.typedTriggerEnabled && canInsert ? .on : .off
        triggerItem.isEnabled = canInsert
        triggerItem.title = canInsert ? "Open by Typing ::" : "Open by Typing :: (enable insertion first)"
    }

    @objc private func openPicker() { onOpenPicker?() }
    @objc private func showSettings() { onShowSettings?() }
    @objc private func showAbout() { onShowAbout?() }

    @objc private func toggleTrigger() {
        services.preferences.update { $0.typedTriggerEnabled.toggle() }
    }
}
